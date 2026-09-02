import { formatReportOne } from "./clone-one";
import { formatReportTwo } from "./clone-two";
import { formatReportThree } from "./clone-three";
import { classify } from "./complex";
import { fromA } from "./a";

export function main(): string {
  return formatReportOne([1], "sum") + formatReportTwo([2], "avg") + formatReportThree([3], "max") + classify(1, 2, 3, "x") + fromA();
}
