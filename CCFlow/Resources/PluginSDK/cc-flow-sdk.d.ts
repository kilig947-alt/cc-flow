export type Capability = string;
export interface SessionSummary { sessionId: string; provider: string; client: string; phase: string; needsAttention: boolean; createdAt: string; lastActivity: string; }
export interface SystemMetrics { cpu: number; memoryPercent: number; memoryUsed: number; memoryTotal: number; loadOne: number; loadFive: number; loadFifteen: number; cores: number; }
export class CCFlowSDKError extends Error { code: string; details?: unknown; }
export const core: { getVersion(): Promise<{sdkVersion:string; schemaVersion:number}>; getCapabilities(): Promise<{declared:Capability[]; granted:Capability[]}> };
export const island: { hint: { show(text:string, duration?:number): Promise<{shown:true}>; clear(): Promise<{cleared:true}> } };
export const system: { getMetrics():Promise<SystemMetrics>; getAppearance():Promise<{colorScheme:"light"|"dark";reduceMotion:boolean;increaseContrast:boolean}>; clipboard:{readText():Promise<{text:string}>;writeText(text:string):Promise<{written:true}>} };
export const apps: { openURL(url:string):Promise<{opened:boolean}>; launch(bundleIdentifier:string):Promise<{launched:boolean}> };
export const sessions: { list():Promise<SessionSummary[]>; focus(sessionId:string):Promise<{focused:boolean}> };
