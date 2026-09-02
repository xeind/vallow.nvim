import { fromA } from "./a";

export function fromB(): string {
  return "b";
}

export function useA(): string {
  return fromA();
}
