import type { PersonalizationOutcomeKind } from './types';

export interface ClassifiedPersonalizationOutcome {
  outcome: PersonalizationOutcomeKind;
  finalText: string;
  confidence: number;
  trainingEligible: boolean;
}

export function classifyPersonalizationOutcome(
  decision: 'accept' | 'reject',
  originalText: string,
  proposedText: string,
  finalText: string
): ClassifiedPersonalizationOutcome {
  const normalizedOriginal = normalizedOutcomeText(originalText);
  const normalizedProposed = normalizedOutcomeText(proposedText);
  const normalizedFinal = normalizedOutcomeText(finalText);

  if (decision === 'accept') {
    if (normalizedFinal === normalizedProposed) {
      return {
        outcome: 'accepted_unchanged',
        finalText,
        confidence: 1,
        trainingEligible: false,
      };
    }
    if (normalizedFinal === normalizedOriginal) {
      return {
        outcome: 'reverted',
        finalText,
        confidence: 0.95,
        trainingEligible: false,
      };
    }
    return {
      outcome: 'accepted_modified',
      finalText,
      confidence: 0.9,
      trainingEligible: normalizedFinal.length > 0,
    };
  }

  if (normalizedFinal === normalizedOriginal) {
    return {
      outcome: 'rejected_unchanged',
      finalText,
      confidence: 0.35,
      trainingEligible: false,
    };
  }
  if (normalizedFinal === normalizedProposed) {
    return {
      outcome: 'later_accepted',
      finalText,
      confidence: 0.9,
      trainingEligible: normalizedFinal.length > 0,
    };
  }
  return {
    outcome: 'rejected_rewritten',
    finalText,
    confidence: 1,
    trainingEligible: normalizedFinal.length > 0,
  };
}

function normalizedOutcomeText(value: string): string {
  return value
    .replace(/\u00a0/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}
