const handler = () => globalThis.webkit?.messageHandlers?.ccFlowRPC;

export class CCFlowSDKError extends Error {
  constructor(code, message, details) {
    super(message);
    this.name = "CCFlowSDKError";
    this.code = code;
    this.details = details;
  }
}

async function call(method, params = {}) {
  const bridge = handler();
  if (!bridge?.postMessage) throw new CCFlowSDKError("BRIDGE_UNAVAILABLE", "CC FLOW Plugin SDK is only available inside a local CC FLOW plugin.");
  const response = await bridge.postMessage({ sdkVersion: "1.0", requestId: crypto.randomUUID(), method, params });
  if (!response?.ok) throw new CCFlowSDKError(response?.error?.code ?? "INTERNAL_ERROR", response?.error?.message ?? "CC FLOW request failed", response?.error?.details);
  return response.result;
}

export const core = {
  getVersion: () => call("core.getVersion"),
  getCapabilities: () => call("core.getCapabilities")
};
export const island = { hint: {
  show: (text, duration = 5000) => call("island.hint.show", { text, duration }),
  clear: () => call("island.hint.clear")
}};
export const system = {
  getMetrics: () => call("system.getMetrics"),
  getAppearance: () => call("system.getAppearance"),
  clipboard: {
    readText: () => call("system.clipboard.readText"),
    writeText: text => call("system.clipboard.writeText", { text })
  }
};
export const apps = {
  openURL: url => call("apps.openURL", { url }),
  launch: bundleIdentifier => call("apps.launch", { bundleIdentifier })
};
export const sessions = {
  list: () => call("sessions.list"),
  focus: sessionId => call("sessions.focus", { sessionId })
};
