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
  if (decision === 'accept') {
    if (finalText === proposedText) {
      return {
        outcome: 'accepted_unchanged',
        finalText,
        confidence: 1,
        trainingEligible: false,
      };
    }
    if (finalText === originalText) {
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
      trainingEligible: finalText.trim().length > 0,
    };
  }

  if (finalText === originalText) {
    return {
      outcome: 'rejected_unchanged',
      finalText,
      confidence: 0.35,
      trainingEligible: false,
    };
  }
  if (finalText === proposedText) {
    return {
      outcome: 'later_accepted',
      finalText,
      confidence: 0.9,
      trainingEligible: finalText.trim().length > 0,
    };
  }
  return {
    outcome: 'rejected_rewritten',
    finalText,
    confidence: 1,
    trainingEligible: finalText.trim().length > 0,
  };
}
