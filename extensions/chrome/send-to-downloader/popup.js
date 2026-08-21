const statusEl = document.getElementById("status");
const sendBtn = document.getElementById("send");

function setStatus(text, isError) {
  statusEl.textContent = text;
  statusEl.classList.toggle("err", Boolean(isError));
}

sendBtn.addEventListener("click", () => {
  setStatus("Sending…");
  chrome.runtime.sendMessage({ type: "queue-active-tab" }, (result) => {
    if (chrome.runtime.lastError) {
      setStatus(chrome.runtime.lastError.message, true);
      return;
    }
    if (!result || !result.ok) {
      setStatus((result && result.error) || "failed", true);
      return;
    }
    const url = (result.entry && result.entry.url) || "queued";
    setStatus(`Queued: ${url}`);
  });
});
