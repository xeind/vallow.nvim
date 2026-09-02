import { fromB } from "./b";

export function fromA(): string {
  return "a" + fromB();
}
