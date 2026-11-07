export const BONUS_GAME_ID = "pink-2026-11-08";
export const BONUS_START = "2026-11-08T14:00:00+05:00";
export const BONUS_PRIZES = [
  { rank: 1, color: "pink", quantity: 10 },
  { rank: 2, color: "pink", quantity: 3 },
  { rank: 3, color: "green", quantity: 5 },
] as const;
export function canDrawBonus(now: Date, count: number, drawn: boolean) {
  return !drawn && count >= 3 && now.getTime() >= Date.parse(BONUS_START);
}
export function bonusCount(raw: string) {
  const count = Number(raw);
  if (!/^\d+$/.test(raw) || !Number.isSafeInteger(count) || count < 1 || count > 100000) throw new Error("Pink case soni 1 dan 100000 gacha bo‘lsin");
  return count;
}
export function pendingPayment(status: string) { return status === "pending"; }