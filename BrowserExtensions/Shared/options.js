const token = document.querySelector("#token");
const status = document.querySelector("#status");
const form = document.querySelector("#pairingForm");
const save = document.querySelector("#save");
chrome.storage.local.get("pairingToken").then((value) => { token.value = value.pairingToken || ""; });
form.addEventListener("submit", async (event) => {
  event.preventDefault();
  const pairingToken = token.value.trim();
  if (!pairingToken) {
    status.dataset.state = "error";
    status.textContent = "请先粘贴配对令牌。";
    token.focus();
    return;
  }
  save.disabled = true;
  status.dataset.state = "";
  status.textContent = "正在连接…";
  try {
    await chrome.storage.local.set({ pairingToken });
    const result = await chrome.runtime.sendMessage({ type: "pairingTokenSaved" });
    status.dataset.state = result?.ok ? "success" : "error";
    status.textContent = result?.ok ? "已连接 CC FLOW。" : "令牌已保存，但暂时无法连接。请确认 CC FLOW 正在运行。";
  } catch (error) {
    status.dataset.state = "error";
    status.textContent = `保存失败：${error?.message || "请重试"}`;
  } finally {
    save.disabled = false;
  }
});
