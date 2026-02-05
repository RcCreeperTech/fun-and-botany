const MAX_INFO_CONSOLE_LINES = 512;
let stdoutBuf = ""
let stderrBuf = ""

function flush(isError) {
  if (!isError) {
    console.log(stdoutBuf);
    stdoutBuf = "";
  } else {
    let style = [
      "color: #eee",
      "background-color: #d20",
      "padding: 2px 4px",
      "border-radius: 2px",
    ].join(";");
    console.log("%c" + stderrBuf, style);
    stderrBuf = ""
  }
};


export function writeToConsole(line, isError) {
  if (!line) return;

  if (isError) {
    stderrBuf += line;
  } else {
    stdoutBuf += line;
  }

  if (line.includes("\n")) flush(isError);
};
