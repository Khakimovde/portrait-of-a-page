CREATE TABLE public.lootzy_mining (
 id uuid PRIMARY KEY, telegram_id bigint NOT NULL REFERENCES public.lootzy_accounts(telegram_id), actor_id bigint NOT NULL, principal_uzs integer NOT NULL CHECK (principal_uzs IN (50000,100000)), rate_uzs integer NOT NULL CHECK (rate_uzs BETWEEN 1000 AND 1000000), payout_cents bigint NOT NULL CHECK (payout_cents > 0), started_at timestamptz NOT NULL DEFAULT now(), ends_at timestamptz NOT NULL DEFAULT (now()+interval '48 hours'), paid_at timestamptz
);
GRANT ALL ON public.lootzy_mining TO service_role;
ALTER TABLE public.lootzy_mining ENABLE ROW LEVEL SECURITY;
CREATE INDEX lootzy_mining_due ON public.lootzy_mining(ends_at) WHERE paid_at IS NULL;
CREATE UNIQUE INDEX lootzy_mining_one_active ON public.lootzy_mining(telegram_id) WHERE paid_at IS NULL;
CREATE OR REPLACE FUNCTION public.lootzy_mining_settle(p_target bigint DEFAULT NULL) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE m public.lootzy_mining; n integer:=0;
BEGIN
FOR m IN SELECT * FROM public.lootzy_mining WHERE paid_at IS NULL AND ends_at<=now() AND (p_target IS NULL OR telegram_id=p_target) ORDER BY telegram_id FOR UPDATE SKIP LOCKED LOOP
 UPDATE public.lootzy_accounts SET balance_cents=balance_cents+m.payout_cents,earned_cents=earned_cents+m.payout_cents,updated_at=now() WHERE telegram_id=m.telegram_id;
 UPDATE public.lootzy_mining SET paid_at=now() WHERE id=m.id;
 n:=n+1;
END LOOP;
RETURN n;
END $$;
REVOKE ALL ON FUNCTION public.lootzy_mining_settle(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lootzy_mining_settle(bigint) TO service_role;
CREATE OR REPLACE FUNCTION public.lootzy_mining_start(p_actor bigint,p_target bigint,p_id uuid,p_principal integer,p_rate integer) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE m public.lootzy_mining;
BEGIN
 IF NOT EXISTS(SELECT 1 FROM public.lootzy_roles WHERE telegram_id=p_actor AND role='admin') THEN RAISE EXCEPTION 'Forbidden'; END IF;
 IF p_id IS NULL OR p_principal IS NULL OR p_principal NOT IN (50000,100000) OR p_rate IS NULL OR p_rate NOT BETWEEN 1000 AND 1000000 THEN RAISE EXCEPTION 'Invalid mining plan or exchange rate'; END IF;
 PERFORM pg_advisory_xact_lock(p_target);
 SELECT * INTO m FROM public.lootzy_mining WHERE id=p_id;
 IF FOUND THEN
  IF m.telegram_id<>p_target OR m.principal_uzs<>p_principal OR m.rate_uzs<>p_rate THEN RAISE EXCEPTION 'Request conflict'; END IF;
  RETURN to_jsonb(m);
 END IF;
 PERFORM public.lootzy_mining_settle(p_target);
 PERFORM 1 FROM public.lootzy_accounts WHERE telegram_id=p_target;
 IF NOT FOUND THEN RAISE EXCEPTION 'Foydalanuvchi topilmadi'; END IF;
 IF EXISTS(SELECT 1 FROM public.lootzy_mining WHERE telegram_id=p_target AND paid_at IS NULL) THEN RAISE EXCEPTION 'Mining allaqachon ishlamoqda'; END IF;
 INSERT INTO public.lootzy_mining(id,telegram_id,actor_id,principal_uzs,rate_uzs,payout_cents) VALUES(p_id,p_target,p_actor,p_principal,p_rate,round(p_principal::numeric*3*100/p_rate)::bigint) RETURNING * INTO m;
 RETURN to_jsonb(m);
END $$;
REVOKE ALL ON FUNCTION public.lootzy_mining_start(bigint,bigint,uuid,integer,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lootzy_mining_start(bigint,bigint,uuid,integer,integer) TO service_role;
CREATE SEQUENCE public.lootzy_withdrawal_queue_seq;
ALTER TABLE public.lootzy_withdrawals ADD COLUMN queue_number bigint, ADD COLUMN queue_started_at timestamptz, ADD COLUMN due_at timestamptz;
WITH ordered AS (SELECT id,row_number() OVER(ORDER BY created_at,id) AS n FROM public.lootzy_withdrawals WHERE status IN ('pending','approved')) UPDATE public.lootzy_withdrawals w SET queue_number=o.n,queue_started_at=now(),due_at=now()+interval '7 days' FROM ordered o WHERE w.id=o.id;
SELECT setval('public.lootzy_withdrawal_queue_seq',coalesce((SELECT max(queue_number) FROM public.lootzy_withdrawals),0)+1,false);
CREATE UNIQUE INDEX lootzy_withdrawal_queue_unique ON public.lootzy_withdrawals(queue_number);
CREATE OR REPLACE FUNCTION public.lootzy_withdrawal_enqueue() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
 NEW.queue_number:=nextval('public.lootzy_withdrawal_queue_seq');
 NEW.queue_started_at:=now(); NEW.due_at:=now()+interval '7 days'; RETURN NEW;
END $$;
CREATE TRIGGER lootzy_withdrawal_enqueue BEFORE INSERT ON public.lootzy_withdrawals FOR EACH ROW EXECUTE FUNCTION public.lootzy_withdrawal_enqueue();
GRANT ALL ON SEQUENCE public.lootzy_withdrawal_queue_seq TO service_role;
COMMENT ON TABLE public.lootzy_bonus_games IS 'DEPRECATED: Pink omad removed from the app; historical rounds and prizes preserved';
COMMENT ON TABLE public.lootzy_bonus_entries IS 'DEPRECATED: historical Pink omad participants preserved';
CREATE EXTENSION IF NOT EXISTS pg_cron;