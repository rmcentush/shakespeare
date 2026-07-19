export interface WritingGapMatch {
  index: number;
  raw: string;
  instruction: string;
}

export const MAX_WRITING_GAP_INSTRUCTION_CHARACTERS = 300;

/**
 * Finds the deliberately narrow `[[...]]` writing-gap syntax. A preceding
 * backslash keeps the brackets literal, and gaps never span paragraphs.
 */
export function findWritingGaps(text: string): WritingGapMatch[] {
  const matches: WritingGapMatch[] = [];
  const pattern = /\[\[([^\]\n]{0,300})\]\]/g;
  let match: RegExpExecArray | null;

  while ((match = pattern.exec(text)) !== null) {
    let backslashes = 0;
    for (let index = match.index - 1; index >= 0 && text[index] === '\\'; index -= 1) {
      backslashes += 1;
    }
    if (backslashes % 2 === 1) continue;

    matches.push({
      index: match.index,
      raw: match[0],
      instruction: match[1].trim(),
    });
  }

  return matches;
}
