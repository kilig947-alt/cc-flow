const token = document.querySelector("#token");
const status = document.querySelector("#status");
chrome.storage.local.get("pairingToken").then((value) => { token.value = value.pairingToken || ""; });
document.querySelector("#save").addEventListener("click", async () => {
  await chrome.storage.local.set({ pairingToken: token.value.trim() });
  status.textContent = " 已保存";
});
