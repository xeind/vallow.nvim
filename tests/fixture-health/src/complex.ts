export function classify(a: number, b: number, c: number, flag: string): string {
  if (a > 0) {
    if (b > 0) {
      if (c > 0) {
        if (flag === "x") {
          return "xpos";
        } else if (flag === "y") {
          return "ypos";
        }
      }
      if (c < 0 && flag !== "") {
        return "cneg";
      }
    } else if (b < 0) {
      for (let i = 0; i < a; i++) {
        if (i % 2 === 0 && c > i) {
          return "even";
        } else if (i % 3 === 0 || c < i) {
          return "third";
        }
      }
    }
  } else if (a < 0) {
    switch (flag) {
      case "a":
        return "na";
      case "b":
        return "nb";
      case "c":
        return "nc";
      default:
        break;
    }
    while (b > 0) {
      b -= 1;
      if (b === c) {
        return "hit";
      }
    }
  }
  return flag ? "flag" : "none";
}
