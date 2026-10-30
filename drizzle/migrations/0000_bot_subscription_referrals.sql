ALTER TABLE public.lootzy_accounts ADD COLUMN IF NOT EXISTS subscribed_at timestamptz;

CREATE TABLE public.lootzy_referrals (
  referred_id bigint PRIMARY KEY REFERENCES public.lootzy_accounts(telegram_id) ON DELETE CASCADE,
  referrer_id bigint NOT NULL REFERENCES public.lootzy_accounts(telegram_id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','confirmed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  confirmed_at timestamptz,
  CHECK (referred_id <> referrer_id)
);
CREATE INDEX lootzy_referrals_referrer_idx ON public.lootzy_referrals(referrer_id, status);
GRANT ALL ON public.lootzy_referrals TO service_role;
ALTER TABLE public.lootzy_referrals ENABLE ROW LEVEL SECURITY;

-- /start in the bot: creates the account; a referral is recorded only for brand-new users.
CREATE OR REPLACE FUNCTION public.lootzy_bot_start(p_id bigint, p_first text, p_last text, p_username text, p_referrer bigint DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE existed boolean; recorded boolean := false;
BEGIN
  SELECT EXISTS(SELECT 1 FROM public.lootzy_accounts WHERE telegram_id=p_id) INTO existed;
  INSERT INTO public.lootzy_accounts(telegram_id, first_name, last_name, username)
  VALUES (p_id, left(coalesce(nullif(p_first,''),'User'),256), left(p_last,256), left(p_username,256))
  ON CONFLICT (telegram_id) DO UPDATE SET first_name=EXCLUDED.first_name, last_name=EXCLUDED.last_name, username=EXCLUDED.username, updated_at=now();
  IF NOT existed AND p_referrer IS NOT NULL AND p_referrer <> p_id AND EXISTS(SELECT 1 FROM public.lootzy_accounts WHERE telegram_id=p_referrer) THEN
    INSERT INTO public.lootzy_referrals(referred_id, referrer_id) VALUES (p_id, p_referrer) ON CONFLICT DO NOTHING;
    recorded := FOUND;
  END IF;
  RETURN jsonb_build_object('new', NOT existed, 'referral_recorded', recorded);
END $$;

-- Called only after Telegram confirms channel membership. Confirms a pending referral once;
-- every 10th confirmed referral grants the referrer one purple key.
CREATE OR REPLACE FUNCTION public.lootzy_confirm_subscription(p_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE ref bigint; total integer := 0; granted boolean := false;
BEGIN
  UPDATE public.lootzy_accounts SET subscribed_at=coalesce(subscribed_at, now()), updated_at=now() WHERE telegram_id=p_id;
  UPDATE public.lootzy_referrals SET status='confirmed', confirmed_at=now()
    WHERE referred_id=p_id AND status='pending' RETURNING referrer_id INTO ref;
  IF ref IS NOT NULL THEN
    PERFORM 1 FROM public.lootzy_accounts WHERE telegram_id=ref FOR UPDATE;
    SELECT count(*) INTO total FROM public.lootzy_referrals WHERE referrer_id=ref AND status='confirmed';
    IF total % 10 = 0 THEN
      UPDATE public.lootzy_accounts SET purple=purple+1, updated_at=now() WHERE telegram_id=ref;
      INSERT INTO public.lootzy_events(id, telegram_id, kind, color, quantity, verified) VALUES (gen_random_uuid(), ref, 'referral_key', 'purple', 1, true);
      granted := true;
    END IF;
  END IF;
  RETURN jsonb_build_object('referrer', ref, 'confirmed_total', total, 'key_granted', granted);
END $$;

REVOKE ALL ON FUNCTION public.lootzy_bot_start(bigint,text,text,text,bigint) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.lootzy_confirm_subscription(bigint) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.lootzy_bot_start(bigint,text,text,text,bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.lootzy_confirm_subscription(bigint) TO service_role;