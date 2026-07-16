const ENDPOINT = "http://127.0.0.1:43128/event";

async function sendEvent(payload) {
  const { pairingToken = "" } = await chrome.storage.local.get("pairingToken");
  if (!pairingToken) return;
  await fetch(ENDPOINT, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ version: 1, token: pairingToken, browser: chrome.runtime.getManifest().name, ...payload })
  });
}

chrome.action.onClicked.addListener((tab) => {
  if (tab.url && /^https?:/.test(tab.url)) {
    sendEvent({ type: "pageSaved", id: String(tab.id || ""), url: tab.url, title: tab.title || "" });
  }
});

chrome.downloads.onCreated.addListener((item) => {
  sendEvent({ type: "download", id: String(item.id), filename: item.filename || "下载", state: item.state || "in_progress",
    receivedBytes: item.bytesReceived || 0, totalBytes: item.totalBytes || 0 });
});

chrome.downloads.onChanged.addListener(async (delta) => {
  const [item] = await chrome.downloads.search({ id: delta.id });
  if (!item) return;
  sendEvent({ type: "download", id: String(item.id), filename: item.filename || "下载", state: item.state || "in_progress",
    receivedBytes: item.bytesReceived || 0, totalBytes: item.totalBytes || 0 });
});
