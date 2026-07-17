import { Editor } from '@tiptap/core';
import { Plugin, PluginKey, Transaction } from '@tiptap/pm/state';
import { Decoration, DecorationSet, EditorView } from '@tiptap/pm/view';
import type { Lint, Linter } from 'harper.js';
import { sendToSwift } from './bridge';
import { hashString } from './utils';

const CHECK_DELAY_MS = 550;
const WORKER_SETUP_TIMEOUT_MS = 8_000;
const MAX_SUGGESTIONS = 5;
const HARPER_RUNTIME_SCRIPT = 'harper-runtime.js';
const HARPER_WASM_DATA_SCRIPT = 'harper-wasm-data.js';
const SuggestionKind = {
  Replace: 0,
  Remove: 1,
  InsertAfter: 2,
} as const;
type SuggestionKindValue = typeof SuggestionKind[keyof typeof SuggestionKind];
const CUSTOM_WORDS_KEY = 'proofreading.harper.customWords.v1';
const IGNORED_LINTS_KEY = 'proofreading.harper.ignoredLints.v1';
const IGNORED_AI_GRAMMAR_KEY = 'proofreading.aiGrammar.ignored.v1';
let isApplyingPersistedUserState = false;

export type ProofreadingDialect =
  | 'american'
  | 'british'
  | 'australian'
  | 'canadian'
  | 'indian';

interface ProofreadingOptions {
  spelling: boolean;
  grammar: boolean;
  dialect: ProofreadingDialect;
}

interface TextBlock {
  id: string;
  from: number;
  to: number;
  text: string;
  textHash: string;
  type: string;
  isHeading: boolean;
}

interface IssueSuggestion {
  kind: SuggestionKindValue;
  replacement: string;
}

interface CachedIssue {
  fromOffset: number;
  toOffset: number;
  kind: string;
  message: string;
  problem: string;
  suggestions: IssueSuggestion[];
  lint: Lint;
}

interface CachedBlockResult {
  text: string;
  issues: CachedIssue[];
}

interface ProofreadingIssue {
  id: string;
  from: number;
  to: number;
  kind: string;
  message: string;
  problem: string;
  suggestions: IssueSuggestion[];
  sourceText: string;
  source: 'harper' | 'ai';
  lint?: Lint;
}

interface AIGrammarIssuePayload {
  id: string;
  from: number;
  to: number;
  kind: string;
  message: string;
  problem: string;
  replacement: string;
}

interface ProofreadingPluginState {
  decorations: DecorationSet;
}

const proofreadingPluginKey = new PluginKey<ProofreadingPluginState>('proofreading');

function dialectValue(dialect: ProofreadingDialect): number {
  switch (dialect) {
    case 'british': return 1;
    case 'australian': return 2;
    case 'canadian': return 3;
    case 'indian': return 4;
    default: return 0;
  }
}

let harperRuntimePromise: Promise<NonNullable<Window['harperRuntime']>> | null = null;
let harperWasmObjectURLPromise: Promise<string> | null = null;

function loadBundledScript(filename: string): Promise<void> {
  return new Promise((resolve, reject) => {
    const script = document.createElement('script');
    script.src = new URL(filename, document.baseURI).href;
    script.async = true;
    script.onload = () => resolve();
    script.onerror = () => reject(new Error(`Unable to load bundled resource: ${filename}`));
    document.head.appendChild(script);
  });
}

function loadHarperRuntime(): Promise<NonNullable<Window['harperRuntime']>> {
  if (window.harperRuntime) return Promise.resolve(window.harperRuntime);
  if (harperRuntimePromise) return harperRuntimePromise;

  harperRuntimePromise = loadBundledScript(HARPER_RUNTIME_SCRIPT).then(() => {
    if (!window.harperRuntime) {
      throw new Error('Harper runtime loaded without registering its API.');
    }
    return window.harperRuntime;
  });
  return harperRuntimePromise;
}

function loadHarperWasmObjectURL(): Promise<string> {
  if (harperWasmObjectURLPromise) return harperWasmObjectURLPromise;

  // WKWebView cannot reliably fetch a file:// WASM binary. The build emits a
  // lazy JS resource containing gzip-compressed bytes, which file:// may load
  // as a normal script. Decompress once and hand Harper a correctly typed blob.
  harperWasmObjectURLPromise = loadBundledScript(HARPER_WASM_DATA_SCRIPT).then(async () => {
    const base64 = window.harperWasmGzipBase64;
    if (!base64) throw new Error('Harper WASM data loaded without registering its bytes.');

    const encoded = window.atob(base64);
    const compressed = new Uint8Array(encoded.length);
    for (let index = 0; index < encoded.length; index += 1) {
      compressed[index] = encoded.charCodeAt(index);
    }
    window.harperWasmGzipBase64 = undefined;

    const decompressedStream = new Blob([compressed])
      .stream()
      .pipeThrough(new DecompressionStream('gzip'));
    const wasm = await new Response(decompressedStream).arrayBuffer();
    return URL.createObjectURL(new Blob([wasm], { type: 'application/wasm' }));
  });
  return harperWasmObjectURLPromise;
}

function normalizedDialect(value: string): ProofreadingDialect {
  switch (value.toLowerCase()) {
    case 'british':
    case 'australian':
    case 'canadian':
    case 'indian':
      return value.toLowerCase() as ProofreadingDialect;
    default:
      return 'american';
  }
}

function isSpellingKind(kind: string): boolean {
  return kind === 'Spelling' || kind === 'Typo';
}

function isObjectiveGrammarKind(kind: string): boolean {
  return kind !== 'Enhancement'
    && kind !== 'Readability'
    && kind !== 'Redundancy'
    && kind !== 'Style';
}

function displayKind(kind: string): string {
  if (isSpellingKind(kind)) return 'Spelling';
  if (kind === 'Capitalization' || kind === 'Punctuation') return kind;
  return 'Grammar';
}

function readStoredString(key: string): string | null {
  try {
    return window.localStorage.getItem(key);
  } catch {
    return null;
  }
}

function writeStoredString(key: string, value: string) {
  try {
    window.localStorage.setItem(key, value);
    if (!isApplyingPersistedUserState) {
      sendToSwift('proofreadingUserStateChanged', {
        json: JSON.stringify({
          customWords: readStoredString(CUSTOM_WORDS_KEY) ?? '[]',
          ignoredLints: readStoredString(IGNORED_LINTS_KEY) ?? '[]',
          ignoredAIGrammar: readStoredString(IGNORED_AI_GRAMMAR_KEY) ?? '[]',
        }),
      });
    }
  } catch {
    // Checking still works when WebKit storage is unavailable; only persistence is lost.
  }
}

export function applyPersistedProofreadingUserState(json: string): boolean {
  try {
    const parsed = JSON.parse(json) as Record<string, unknown>;
    const values = [parsed.customWords, parsed.ignoredLints, parsed.ignoredAIGrammar];
    if (!values.every((value) => typeof value === 'string')) return false;

    isApplyingPersistedUserState = true;
    window.localStorage.setItem(CUSTOM_WORDS_KEY, parsed.customWords as string);
    window.localStorage.setItem(IGNORED_LINTS_KEY, parsed.ignoredLints as string);
    window.localStorage.setItem(IGNORED_AI_GRAMMAR_KEY, parsed.ignoredAIGrammar as string);
    return true;
  } catch {
    return false;
  } finally {
    isApplyingPersistedUserState = false;
  }
}

function storedCustomWords(): string[] {
  const raw = readStoredString(CUSTOM_WORDS_KEY);
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed)
      ? parsed.filter((word): word is string => typeof word === 'string' && word.trim().length > 0)
      : [];
  } catch {
    return [];
  }
}

function storedIgnoredAIGrammarIssues(): Set<string> {
  const raw = readStoredString(IGNORED_AI_GRAMMAR_KEY);
  if (!raw) return new Set();
  try {
    const parsed = JSON.parse(raw);
    return new Set(Array.isArray(parsed) ? parsed.filter((item) => typeof item === 'string') : []);
  } catch {
    return new Set();
  }
}

function aiGrammarFingerprint(problem: string, replacement: string): string {
  return `${problem}\u0000${replacement}`;
}

export function unicodeScalarOffsetToUTF16(text: string, scalarOffset: number): number {
  if (scalarOffset <= 0) return 0;
  let scalars = 0;
  let utf16Offset = 0;
  for (const scalar of text) {
    if (scalars >= scalarOffset) break;
    utf16Offset += scalar.length;
    scalars += 1;
  }
  return utf16Offset;
}

function collectTextBlocks(editor: Editor): TextBlock[] {
  const blocks: TextBlock[] = [];
  editor.state.doc.descendants((node, position) => {
    if (!node.isTextblock) return true;
    if (node.type.spec.code || node.type.name === 'codeBlock') return false;

    const text = node.textBetween(0, node.content.size, '\n', '\n');
    if (text.trim()) {
      blocks.push({
        id: `grammar_block_${position + 1}`,
        from: position + 1,
        to: position + node.nodeSize - 1,
        text,
        textHash: hashString(text),
        type: node.type.name,
        isHeading: node.type.name === 'heading',
      });
    }
    return false;
  });
  return blocks;
}

function issueDecorations(doc: any, issues: ProofreadingIssue[]): DecorationSet {
  const decorations = issues
    .filter((issue) => issue.from < issue.to && issue.to <= doc.content.size)
    .map((issue) => Decoration.inline(issue.from, issue.to, {
      class: isSpellingKind(issue.kind)
        ? 'proofreading-issue proofreading-spelling'
        : 'proofreading-issue proofreading-grammar',
      'data-proofreading-id': issue.id,
      'aria-label': `${displayKind(issue.kind)}: ${issue.message}`,
    }));
  return DecorationSet.create(doc, decorations);
}

function proofreadingPlugin(controller: ProofreadingController): Plugin<ProofreadingPluginState> {
  return new Plugin<ProofreadingPluginState>({
    key: proofreadingPluginKey,
    state: {
      init: () => ({ decorations: DecorationSet.empty }),
      apply(transaction, state) {
        if (transaction.docChanged) {
          return { decorations: controller.mapIssuesThrough(transaction) };
        }
        const issues = transaction.getMeta(proofreadingPluginKey) as ProofreadingIssue[] | undefined;
        if (issues) {
          return { decorations: issueDecorations(transaction.doc, issues) };
        }
        return state;
      },
    },
    props: {
      decorations(state) {
        return proofreadingPluginKey.getState(state)?.decorations ?? DecorationSet.empty;
      },
      handleDOMEvents: {
        click(_view, event) {
          return controller.handleEditorClick(event);
        },
        keydown(_view, event) {
          if (event.key === 'Escape') return controller.hidePopover();
          if (event.key !== 'F8') return false;
          event.preventDefault();
          controller.focusRelativeIssue(event.shiftKey ? -1 : 1);
          return true;
        },
      },
    },
    view(view) {
      controller.bindView(view);
      return {
        update(updatedView, previousState) {
          if (updatedView.state.doc !== previousState.doc) {
            controller.documentDidChange();
          }
        },
        destroy() {
          controller.destroy();
        },
      };
    },
  });
}

class ProofreadingController {
  private editor: Editor;
  private view: EditorView | null = null;
  private linterPromise: Promise<Linter> | null = null;
  private blockCache = new Map<string, CachedBlockResult>();
  private issues: ProofreadingIssue[] = [];
  private grammarIssues: ProofreadingIssue[] = [];
  private options: ProofreadingOptions = {
    spelling: false,
    grammar: false,
    dialect: 'american',
  };
  private timer: number | null = null;
  private runToken = 0;
  private popover: HTMLDivElement | null = null;
  private destroyed = false;
  private boundHidePopover = () => { this.hidePopover(); };

  constructor(editor: Editor) {
    this.editor = editor;
  }

  bindView(view: EditorView) {
    this.view = view;
    document.addEventListener('scroll', this.boundHidePopover, true);
    window.addEventListener('resize', this.boundHidePopover);
  }

  documentDidChange() {
    this.hidePopover();
    this.scheduleCheck(CHECK_DELAY_MS);
  }

  mapIssuesThrough(transaction: Transaction): DecorationSet {
    const mapIssues = (source: ProofreadingIssue[]): ProofreadingIssue[] => {
      const retained: ProofreadingIssue[] = [];
      for (const issue of source) {
      const mappedFrom = transaction.mapping.mapResult(issue.from, 1);
      const mappedTo = transaction.mapping.mapResult(issue.to, -1);
      const currentText = transaction.doc.textBetween(mappedFrom.pos, mappedTo.pos, '\n', '\n');

      if (
        mappedFrom.deletedAcross ||
        mappedTo.deletedAcross ||
        mappedFrom.pos >= mappedTo.pos ||
        currentText !== issue.problem
      ) {
        continue;
      }

      issue.from = mappedFrom.pos;
      issue.to = mappedTo.pos;
      retained.push(issue);
      }
      return retained;
    }

    this.issues = mapIssues(this.issues);
    this.grammarIssues = mapIssues(this.grammarIssues);
    return issueDecorations(transaction.doc, this.allIssues());
  }

  setAIGrammarIssues(json: string) {
    let payloads: AIGrammarIssuePayload[] = [];
    try {
      const parsed = JSON.parse(json);
      if (Array.isArray(parsed)) payloads = parsed;
    } catch {
      payloads = [];
    }

    const ignored = storedIgnoredAIGrammarIssues();
    this.grammarIssues = payloads.flatMap((payload): ProofreadingIssue[] => {
      if (
        typeof payload.id !== 'string'
        || typeof payload.from !== 'number'
        || typeof payload.to !== 'number'
        || typeof payload.problem !== 'string'
        || typeof payload.replacement !== 'string'
        || payload.from >= payload.to
        || payload.to > this.editor.state.doc.content.size
        || ignored.has(aiGrammarFingerprint(payload.problem, payload.replacement))
      ) return [];

      const current = this.editor.state.doc.textBetween(payload.from, payload.to, '\n', '\n');
      if (current !== payload.problem || payload.problem === payload.replacement) return [];

      return [{
        id: payload.id,
        from: payload.from,
        to: payload.to,
        kind: payload.kind || 'Grammar',
        message: payload.message || 'Grammar suggestion',
        problem: payload.problem,
        suggestions: [{ kind: SuggestionKind.Replace, replacement: payload.replacement }],
        sourceText: current,
        source: 'ai',
      }];
    });
    this.dispatchIssues();
    this.emitStatus('ready', this.allIssues().length);
  }

  setOptions(spelling: boolean, grammar: boolean, dialect: string) {
    const nextDialect = normalizedDialect(dialect);
    const dialectChanged = nextDialect !== this.options.dialect;
    this.options = { spelling, grammar, dialect: nextDialect };

    if (!spelling && !grammar) {
      this.runToken += 1;
      this.clearIssues(true);
      this.emitStatus(this.grammarIssues.length > 0 ? 'ready' : 'disabled', this.grammarIssues.length);
      return;
    }

    void this.getLinter();

    if (dialectChanged) {
      this.runToken += 1;
      this.clearBlockCache();
      void this.applyDialect(nextDialect);
    } else {
      this.scheduleCheck(0);
    }
  }

  resetDictionary() {
    writeStoredString(CUSTOM_WORDS_KEY, '[]');
    writeStoredString(IGNORED_LINTS_KEY, '[]');
    writeStoredString(IGNORED_AI_GRAMMAR_KEY, '[]');
    void this.getLinter().then(async (linter) => {
      await linter.clearWords();
      await linter.clearIgnoredLints();
      this.clearBlockCache();
      this.scheduleCheck(0);
    });
  }

  reloadUserState() {
    this.runToken += 1;
    const previousLinter = this.linterPromise;
    this.linterPromise = null;
    void previousLinter?.then((linter) => linter.dispose()).catch(() => {});
    this.clearBlockCache();
    this.dispatchIssues();
    this.scheduleCheck(0);
  }

  focusRelativeIssue(delta: number) {
    const issues = this.allIssues().sort((left, right) => left.from - right.from || left.to - right.to);
    if (issues.length === 0) return;
    const currentPosition = this.editor.state.selection.from;
    let index = delta < 0
      ? -1
      : issues.findIndex((issue) => issue.from > currentPosition);
    if (delta < 0) {
      for (let candidate = issues.length - 1; candidate >= 0; candidate -= 1) {
        if (issues[candidate].from < currentPosition) {
          index = candidate;
          break;
        }
      }
    }
    if (index < 0) index = delta < 0 ? issues.length - 1 : 0;
    const issue = issues[index];
    this.editor.commands.setTextSelection({ from: issue.from, to: issue.to });
    this.editor.commands.focus();
    window.requestAnimationFrame(() => {
      const elements = document.querySelectorAll<HTMLElement>('[data-proofreading-id]');
      const target = [...elements].find((element) => element.dataset.proofreadingId === issue.id);
      if (target) this.showPopover(issue, target.getBoundingClientRect());
    });
  }

  grammarContextJSON(): string {
    return JSON.stringify({ blocks: collectTextBlocks(this.editor) });
  }

  handleEditorClick(event: MouseEvent): boolean {
    const target = event.target instanceof Element
      ? event.target.closest('[data-proofreading-id]')
      : null;
    if (!(target instanceof HTMLElement)) {
      this.hidePopover();
      return false;
    }

    const issue = this.allIssues().find((candidate) => candidate.id === target.dataset.proofreadingId);
    if (!issue) return false;

    // Proofreading decorations are presentation only. In particular, they must
    // not claim clicks that ProseMirror needs for caret placement or text
    // selection; otherwise annotated text can appear impossible to delete.
    if (!document.getSelection()?.isCollapsed) {
      this.hidePopover();
      return false;
    }

    this.showPopover(issue, target.getBoundingClientRect());
    return false;
  }

  hidePopover(): boolean {
    if (!this.popover || this.popover.hidden) return false;
    this.popover.hidden = true;
    this.popover.replaceChildren();
    return true;
  }

  destroy() {
    if (this.destroyed) return;
    this.destroyed = true;
    this.runToken += 1;
    if (this.timer !== null) window.clearTimeout(this.timer);
    document.removeEventListener('scroll', this.boundHidePopover, true);
    window.removeEventListener('resize', this.boundHidePopover);
    this.clearIssues(false);
    this.clearBlockCache();
    this.popover?.remove();
    this.popover = null;
    void this.linterPromise?.then((linter) => linter.dispose()).catch(() => {});
  }

  private getLinter(): Promise<Linter> {
    if (!this.linterPromise) this.linterPromise = this.createLinter();
    return this.linterPromise;
  }

  private async createLinter(): Promise<Linter> {
    const [runtime, wasmURL] = await Promise.all([
      loadHarperRuntime(),
      loadHarperWasmObjectURL(),
    ]);
    const dialect = dialectValue(this.options.dialect);

    let candidate = runtime.createWorkerLinter(wasmURL, dialect);
    try {
      await Promise.race([
        candidate.setup(),
        new Promise<never>((_, reject) => {
          window.setTimeout(() => reject(new Error('Harper worker setup timed out')), WORKER_SETUP_TIMEOUT_MS);
        }),
      ]);
    } catch (workerError) {
      console.warn('Proofreading worker unavailable; using the local engine.', workerError);
      await candidate.dispose().catch(() => {});
      candidate = runtime.createLocalLinter(wasmURL, dialect);
      await candidate.setup();
    }

    const customWords = storedCustomWords();
    if (customWords.length > 0) await candidate.importWords(customWords);
    const ignoredLints = readStoredString(IGNORED_LINTS_KEY);
    if (ignoredLints) {
      await candidate.importIgnoredLints(ignoredLints).catch(() => {});
    }

    return candidate;
  }

  private async applyDialect(dialect: ProofreadingDialect) {
    try {
      const linter = await this.getLinter();
      await linter.setDialect(dialectValue(dialect));
      const customWords = storedCustomWords();
      if (customWords.length > 0) await linter.importWords(customWords);
      const ignoredLints = readStoredString(IGNORED_LINTS_KEY);
      if (ignoredLints) await linter.importIgnoredLints(ignoredLints).catch(() => {});
      this.scheduleCheck(0);
    } catch (error) {
      this.emitError(error);
    }
  }

  private scheduleCheck(delay: number) {
    if (this.destroyed || (!this.options.spelling && !this.options.grammar)) return;
    if (this.timer !== null) window.clearTimeout(this.timer);
    const token = ++this.runToken;
    this.timer = window.setTimeout(() => {
      this.timer = null;
      void this.runCheck(token);
    }, delay);
  }

  private async runCheck(token: number) {
    if (this.destroyed || token !== this.runToken) return;
    this.emitStatus('checking', this.allIssues().length);

    try {
      const linter = await this.getLinter();
      const blocks = collectTextBlocks(this.editor);
      const activeCacheKeys = new Set<string>();
      const collected: ProofreadingIssue[] = [];

      for (const block of blocks) {
        if (this.destroyed || token !== this.runToken) {
          return;
        }

        const cacheKey = `${block.type}\u0000${block.textHash}\u0000${block.text}`;
        activeCacheKeys.add(cacheKey);
        let cached = this.blockCache.get(cacheKey);
        if (!cached) {
          const lints = await linter.lint(block.text, {
            language: 'plaintext',
            forceAllHeadings: block.isHeading,
            dedup: true,
          });
          cached = { text: block.text, issues: this.convertLintsToCached(lints, block) };
          this.blockCache.set(cacheKey, cached);
        } else {
          // Refresh insertion order so the bounded cache behaves as an LRU.
          this.blockCache.delete(cacheKey);
          this.blockCache.set(cacheKey, cached);
        }
        collected.push(...this.positionCachedIssues(cached, block, token));
      }

      if (this.destroyed || token !== this.runToken) {
        return;
      }

      this.issues = collected;
      this.pruneBlockCache(activeCacheKeys);
      this.dispatchIssues();
      this.emitStatus('ready', this.allIssues().length);
    } catch (error) {
      if (token === this.runToken) this.emitError(error);
    }
  }

  private convertLintsToCached(lints: Lint[], block: TextBlock): CachedIssue[] {
    const issues: CachedIssue[] = [];
    for (let index = 0; index < lints.length; index += 1) {
      const lint = lints[index];
      const kind = lint.lint_kind();
      const spelling = isSpellingKind(kind);
      if (!spelling && !isObjectiveGrammarKind(kind)) {
        lint.free();
        continue;
      }

      const span = lint.span();
      const fromOffset = unicodeScalarOffsetToUTF16(block.text, span.start);
      const toOffset = unicodeScalarOffsetToUTF16(block.text, span.end);
      span.free();
      if (fromOffset >= toOffset || block.from + toOffset > block.to) {
        lint.free();
        continue;
      }

      const allSuggestions = lint.suggestions();
      const rawSuggestions = allSuggestions.slice(0, MAX_SUGGESTIONS);
      const suggestions = rawSuggestions.map((suggestion) => ({
        kind: suggestion.kind(),
        replacement: suggestion.get_replacement_text(),
      }));
      allSuggestions.forEach((suggestion) => suggestion.free());

      issues.push({
        fromOffset,
        toOffset,
        kind,
        message: lint.message(),
        problem: lint.get_problem_text(),
        suggestions,
        lint,
      });
    }
    return issues;
  }

  private positionCachedIssues(
    cached: CachedBlockResult,
    block: TextBlock,
    token: number
  ): ProofreadingIssue[] {
    return cached.issues.flatMap((issue, index) => {
      const spelling = isSpellingKind(issue.kind);
      if (spelling ? !this.options.spelling : !this.options.grammar) return [];
      return [{
        id: `proof_${token}_${block.from}_${issue.fromOffset}_${index}`,
        from: block.from + issue.fromOffset,
        to: block.from + issue.toOffset,
        kind: issue.kind,
        message: issue.message,
        problem: issue.problem,
        suggestions: issue.suggestions,
        sourceText: cached.text,
        source: 'harper' as const,
        lint: issue.lint,
      }];
    });
  }

  private pruneBlockCache(activeKeys: Set<string>) {
    for (const [key, cached] of this.blockCache) {
      if (!activeKeys.has(key)) {
        this.freeCachedBlock(cached);
        this.blockCache.delete(key);
      }
    }
  }

  private clearBlockCache() {
    for (const cached of this.blockCache.values()) this.freeCachedBlock(cached);
    this.blockCache.clear();
    this.issues = [];
  }

  private freeCachedBlock(cached: CachedBlockResult) {
    for (const issue of cached.issues) issue.lint.free();
  }

  private dispatchIssues() {
    const view = this.view ?? this.editor.view;
    view.dispatch(view.state.tr.setMeta(proofreadingPluginKey, this.allIssues()));
  }

  private allIssues(): ProofreadingIssue[] {
    return [...this.issues, ...this.grammarIssues];
  }

  private clearIssues(dispatch: boolean) {
    this.issues = [];
    if (dispatch && !this.destroyed) this.dispatchIssues();
  }

  private emitStatus(status: 'checking' | 'ready' | 'disabled', issueCount: number) {
    sendToSwift('proofreadingUpdate', { status, issueCount, message: '' });
  }

  private emitError(error: unknown) {
    const message = error instanceof Error ? error.message : String(error);
    console.error('Proofreading failed', error);
    sendToSwift('proofreadingUpdate', { status: 'error', issueCount: 0, message });
  }

  private ensurePopover(): HTMLDivElement {
    if (this.popover) return this.popover;
    const popover = document.createElement('div');
    popover.id = 'proofreading-popover';
    popover.hidden = true;
    popover.contentEditable = 'false';
    popover.setAttribute('role', 'dialog');
    popover.setAttribute('aria-label', 'Writing suggestion');
    document.body.appendChild(popover);
    this.popover = popover;
    return popover;
  }

  private showPopover(issue: ProofreadingIssue, anchor: DOMRect) {
    const popover = this.ensurePopover();
    popover.replaceChildren();

    const header = document.createElement('div');
    header.className = 'proofreading-popover-header';
    const kind = document.createElement('span');
    kind.className = `proofreading-kind ${isSpellingKind(issue.kind) ? 'is-spelling' : 'is-grammar'}`;
    kind.textContent = displayKind(issue.kind);
    const close = document.createElement('button');
    close.type = 'button';
    close.className = 'proofreading-close';
    close.textContent = '×';
    close.title = 'Close';
    close.addEventListener('click', () => this.hidePopover());
    header.append(kind, close);

    const message = document.createElement('p');
    message.className = 'proofreading-message';
    message.textContent = issue.message;
    popover.append(header, message);

    if (issue.suggestions.length > 0) {
      const suggestions = document.createElement('div');
      suggestions.className = 'proofreading-suggestions';
      for (const suggestion of issue.suggestions) {
        const button = document.createElement('button');
        button.type = 'button';
        button.className = 'proofreading-suggestion';
        button.textContent = suggestion.replacement || 'Delete';
        button.addEventListener('click', () => this.applySuggestion(issue, suggestion));
        suggestions.appendChild(button);
      }
      popover.appendChild(suggestions);
    }

    const footer = document.createElement('div');
    footer.className = 'proofreading-popover-footer';
    const ignore = document.createElement('button');
    ignore.type = 'button';
    ignore.className = 'proofreading-secondary-action';
    ignore.textContent = 'Ignore';
    ignore.addEventListener('click', () => { void this.ignoreIssue(issue); });
    footer.appendChild(ignore);

    if (isSpellingKind(issue.kind) && /^[\p{L}\p{M}'’-]+$/u.test(issue.problem.trim())) {
      const addWord = document.createElement('button');
      addWord.type = 'button';
      addWord.className = 'proofreading-secondary-action';
      addWord.textContent = 'Add to dictionary';
      addWord.addEventListener('click', () => { void this.addToDictionary(issue.problem.trim()); });
      footer.appendChild(addWord);
    }
    popover.appendChild(footer);

    popover.hidden = false;
    const margin = 10;
    const gap = 8;
    const width = popover.offsetWidth;
    const height = popover.offsetHeight;
    const left = Math.min(Math.max(anchor.left, margin), window.innerWidth - width - margin);
    let top = anchor.bottom + gap;
    if (top + height > window.innerHeight - margin) {
      top = Math.max(margin, anchor.top - height - gap);
    }
    popover.style.left = `${left}px`;
    popover.style.top = `${top}px`;
  }

  private applySuggestion(issue: ProofreadingIssue, suggestion: IssueSuggestion) {
    const current = this.editor.state.doc.textBetween(issue.from, issue.to, '\n', '\n');
    if (current !== issue.problem) {
      this.hidePopover();
      this.scheduleCheck(0);
      return;
    }

    const transaction = this.editor.state.tr;
    if (suggestion.kind === SuggestionKind.InsertAfter) {
      transaction.insertText(suggestion.replacement, issue.to);
    } else {
      transaction.insertText(suggestion.replacement, issue.from, issue.to);
    }
    this.editor.view.dispatch(transaction);
    this.editor.commands.focus();
    this.hidePopover();
  }

  private async ignoreIssue(issue: ProofreadingIssue) {
    if (issue.source === 'ai') {
      const ignored = storedIgnoredAIGrammarIssues();
      const replacement = issue.suggestions[0]?.replacement ?? '';
      ignored.add(aiGrammarFingerprint(issue.problem, replacement));
      writeStoredString(IGNORED_AI_GRAMMAR_KEY, JSON.stringify([...ignored]));
      this.grammarIssues = this.grammarIssues.filter((candidate) => candidate.id !== issue.id);
      this.hidePopover();
      this.dispatchIssues();
      this.emitStatus('ready', this.allIssues().length);
      return;
    }

    try {
      const linter = await this.getLinter();
      if (!issue.lint) return;
      await linter.ignoreLint(issue.sourceText, issue.lint);
      writeStoredString(IGNORED_LINTS_KEY, await linter.exportIgnoredLints());
      this.clearBlockCache();
      this.hidePopover();
      this.scheduleCheck(0);
    } catch (error) {
      this.emitError(error);
    }
  }

  private async addToDictionary(word: string) {
    try {
      const linter = await this.getLinter();
      await linter.importWords([word]);
      writeStoredString(CUSTOM_WORDS_KEY, JSON.stringify(await linter.exportWords()));
      this.clearBlockCache();
      this.hidePopover();
      this.scheduleCheck(0);
    } catch (error) {
      this.emitError(error);
    }
  }

}

export interface ProofreadingControllerAPI {
  setOptions(spelling: boolean, grammar: boolean, dialect: string): void;
  setAIGrammarIssues(json: string): void;
  resetDictionary(): void;
  reloadUserState(): void;
  grammarContextJSON(): string;
}

export function attachProofreading(editor: Editor): ProofreadingControllerAPI {
  const controller = new ProofreadingController(editor);
  editor.registerPlugin(proofreadingPlugin(controller));
  return controller;
}
