import type { Tables } from "@/integrations/supabase/types";

export type Account = Tables<"lootzy_accounts">;
export type Withdrawal = Tables<"lootzy_withdrawals"> & { account?: Account };
export type Overview = { day: string; users: number; reportedAds: number; verifiedAds: number; keys: number; pending: number };
export type CloudResult = { account: Account; isAdmin: boolean; withdrawals: Withdrawal[]; ads: number; reportedAds?: number; referrals?: { invited: number; confirmed: number; keys: number }; reward?: number; overview?: Overview; users?: Account[]; events?: Tables<"lootzy_events">[] };
export type CloudRequest = { action: "me" | "overview" | "search" | "detail" | "grant" | "withdraw" | "decision" | "open" | "ad_report"; target?: number; query?: string; color?: string; quantity?: number; amount?: number; method?: string; destination?: string; status?: string; id?: string };

export async function cloudCall(initData: string, input: CloudRequest): Promise<CloudResult> {
  const base = import.meta.env["VITE_LOOTZY_API_URL"] ?? "";
  const response = await fetch(`${base}/api/public/lootzy`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ...input, initData }) });
  const result = await response.json();
  if (!response.ok) throw new Error(result.error ?? "Xizmatga ulanib bo‘lmadi");
  return result;
}