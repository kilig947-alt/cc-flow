const ENDPOINT = "http://127.0.0.1:43128/event";

async function sendEvent(payload) {
  const { pairingToken = "" } = await chrome.storage.local.get("pairingToken");
  if (!pairingToken) return false;
  try {
    const response = await fetch(ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ version: 1, token: pairingToken, browser: chrome.runtime.getManifest().name, ...payload })
    });
    return response.ok;
  } catch (_) {
    return false;
  }
}

const sendHeartbeat = () => sendEvent({ type: "heartbeat" });
chrome.runtime.onInstalled.addListener(sendHeartbeat);
chrome.runtime.onStartup.addListener(sendHeartbeat);
chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type !== "pairingTokenSaved") return false;
  sendHeartbeat().then((ok) => sendResponse({ ok }));
  return true;
});
chrome.storage.onChanged.addListener((changes, areaName) => {
  if (areaName === "local" && changes.pairingToken) sendHeartbeat();
});
if (chrome.alarms) {
  chrome.alarms.create("ccFlowHeartbeat", { periodInMinutes: 0.5 });
  chrome.alarms.onAlarm.addListener((alarm) => {
    if (alarm.name === "ccFlowHeartbeat") sendHeartbeat();
  });
} else {
  setInterval(sendHeartbeat, 30_000);
}
sendHeartbeat();

async function showActionFeedback(text, color) {
  await chrome.action.setBadgeBackgroundColor({ color });
  await chrome.action.setBadgeText({ text });
  setTimeout(() => chrome.action.setBadgeText({ text: "" }), 1800);
}

chrome.action.onClicked.addListener(async (tab) => {
  const { pairingToken = "" } = await chrome.storage.local.get("pairingToken");
  if (!pairingToken.trim()) {
    await chrome.runtime.openOptionsPage();
    return;
  }
  if (!tab.url || !/^https?:/.test(tab.url)) {
    await showActionFeedback("!", "#b42318");
    return;
  }
  const ok = await sendEvent({ type: "pageSaved", id: String(tab.id || ""), url: tab.url, title: tab.title || "" });
  await showActionFeedback(ok ? "✓" : "!", ok ? "#067647" : "#b42318");
});

if (chrome.downloads) {
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
}
