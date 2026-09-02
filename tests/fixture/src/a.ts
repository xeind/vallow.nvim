export type Dead = { id: string };

export function usedFn(): number {
  return 1;
}

export function unusedFn(): number {
  return 2;
}
