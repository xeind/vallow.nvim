import { missing } from "./nope";
import { usedFn } from "./a";

export function main(): string {
  return missing + usedFn();
}
