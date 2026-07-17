interface PositionedBlock {
  type: string;
  from: number;
  to: number;
}

function nearestBlockIndex<T extends PositionedBlock>(blocks: T[], cursorPosition: number): number {
  const containing = blocks.findIndex(
    (block) => cursorPosition >= block.from && cursorPosition <= block.to
  );
  if (containing >= 0) return containing;

  return blocks.reduce((nearest, block, index) => {
    const distance = cursorPosition < block.from
      ? block.from - cursorPosition
      : cursorPosition - block.to;
    const nearestBlock = blocks[nearest];
    const nearestDistance = cursorPosition < nearestBlock.from
      ? nearestBlock.from - cursorPosition
      : cursorPosition - nearestBlock.to;
    return distance < nearestDistance ? index : nearest;
  }, 0);
}

function evenlySpacedIndices(count: number, requested: number): number[] {
  if (count <= 0 || requested <= 0) return [];
  if (requested === 1) return [0];
  const result = new Set<number>();
  for (let index = 0; index < requested; index += 1) {
    result.add(Math.round((index * (count - 1)) / (requested - 1)));
  }
  return Array.from(result);
}

/**
 * Keeps the active passage, nearby continuity, headings, and sparse whole-draft
 * checkpoints while honoring a strict bridge budget.
 */
export function selectEditContextBlocks<T extends PositionedBlock>(
  blocks: T[],
  cursorPosition: number,
  maximumBlocks: number
): T[] {
  if (maximumBlocks <= 0 || blocks.length === 0) return [];
  if (blocks.length <= maximumBlocks) return blocks;

  const targetIndex = nearestBlockIndex(blocks, cursorPosition);
  const selected = new Set<number>();
  const add = (index: number) => {
    if (index >= 0 && index < blocks.length && selected.size < maximumBlocks) {
      selected.add(index);
    }
  };

  add(targetIndex);
  for (let distance = 1; distance <= 28; distance += 1) {
    add(targetIndex - distance);
    add(targetIndex + distance);
  }

  for (let index = 0; index < 4; index += 1) {
    add(index);
    add(blocks.length - 1 - index);
  }

  blocks
    .map((block, index) => ({ block, index }))
    .filter(({ block }) => block.type === 'heading')
    .sort((left, right) => Math.abs(left.index - targetIndex) - Math.abs(right.index - targetIndex))
    .slice(0, 36)
    .forEach(({ index }) => add(index));

  evenlySpacedIndices(blocks.length, Math.min(64, maximumBlocks)).forEach(add);

  for (let distance = 0; selected.size < maximumBlocks && distance < blocks.length; distance += 1) {
    add(targetIndex - distance);
    add(targetIndex + distance);
  }

  return Array.from(selected)
    .sort((left, right) => left - right)
    .map((index) => blocks[index]);
}
