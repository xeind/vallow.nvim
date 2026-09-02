export function formatReportThree(rows: number[], mode: string): string {
  const out: string[] = [];
  let total = 0;
  for (const row of rows) {
    total += row;
    if (row > 100) {
      out.push("big " + row);
    } else if (row > 10) {
      out.push("mid " + row);
    } else {
      out.push("small " + row);
    }
  }
  if (mode === "sum") {
    out.push("total " + total);
  }
  if (mode === "avg") {
    out.push("avg " + total / rows.length);
  }
  if (mode === "max") {
    out.push("max " + Math.max(...rows));
  }
  if (mode === "min") {
    out.push("min " + Math.min(...rows));
  }
  out.push("count " + rows.length);
  out.push("mode " + mode);
  return out.join("\n");
}
