CREATE TABLE public.lootzy_bonus_games (
 id text PRIMARY KEY DEFAULT 'pink-2026-11-08', drawn_at timestamptz, drawn_by bigint
);
GRANT ALL ON public.lootzy_bonus_games TO service_role;
ALTER TABLE public.lootzy_bonus_games ENABLE ROW LEVEL SECURITY;
CREATE TABLE public.lootzy_bonus_entries (
 game_id text NOT NULL REFERENCES public.lootzy_bonus_games(id),
 telegram_id bigint NOT NULL REFERENCES public.lootzy_accounts(telegram_id),
 pink_count integer NOT NULL CHECK (pink_count BETWEEN 1 AND 100000),
 added_by bigint NOT NULL, created_at timestamptz NOT NULL DEFAULT now(),
 rank integer CHECK (rank BETWEEN 1 AND 3),
 PRIMARY KEY (game_id, telegram_id), UNIQUE (game_id, rank)
);
GRANT ALL ON public.lootzy_bonus_entries TO service_role;
ALTER TABLE public.lootzy_bonus_entries ENABLE ROW LEVEL SECURITY;
CREATE OR REPLACE FUNCTION public.lootzy_bonus_manage(p_actor bigint, p_action text, p_target bigint DEFAULT NULL, p_quantity integer DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
 v_game text := 'pink-2026-11-08'; v_drawn timestamptz; v_id bigint; v_rank integer; v_total bigint; v_ticket double precision; v_qty integer; v_color text;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.lootzy_roles WHERE telegram_id=p_actor AND role='admin') THEN RAISE EXCEPTION 'Admin uchun ruxsat yo‘q'; END IF;
 IF p_action NOT IN ('add','draw') OR p_action IS NULL THEN RAISE EXCEPTION 'Noto‘g‘ri amal'; END IF;
 PERFORM pg_advisory_xact_lock(811202614);
 INSERT INTO public.lootzy_bonus_games(id) VALUES(v_game) ON CONFLICT DO NOTHING;
 SELECT drawn_at INTO v_drawn FROM public.lootzy_bonus_games WHERE id=v_game FOR UPDATE;
 IF v_drawn IS NOT NULL THEN
   IF p_action='draw' THEN RETURN jsonb_build_object('drawn',true,'replayed',true); END IF;
   RAISE EXCEPTION 'O‘yin yakunlangan';
 END IF;
 IF p_action='add' THEN
   IF p_quantity IS NULL OR p_quantity < 1 OR p_quantity > 100000 THEN RAISE EXCEPTION 'Kamida 1 ta pink case, ko‘pi bilan 100000'; END IF;
   IF NOT EXISTS (SELECT 1 FROM public.lootzy_accounts WHERE telegram_id=p_target) THEN RAISE EXCEPTION 'ID topilmadi. Foydalanuvchi botga /start bosishi kerak'; END IF;
   INSERT INTO public.lootzy_bonus_entries(game_id,telegram_id,pink_count,added_by) VALUES(v_game,p_target,p_quantity,p_actor)
   ON CONFLICT (game_id,telegram_id) DO UPDATE SET pink_count=excluded.pink_count, added_by=excluded.added_by;
   RETURN jsonb_build_object('saved',true);
 END IF;
 IF now() < '2026-11-08 14:00:00+05'::timestamptz THEN RAISE EXCEPTION 'O‘yin 08.11.2026 soat 14:00 (Toshkent) dan keyin boshlanadi'; END IF;
 IF (SELECT count(*) FROM public.lootzy_bonus_entries WHERE game_id=v_game) < 3 THEN RAISE EXCEPTION 'Kamida 3 ta ishtirokchi kerak'; END IF;
 FOR v_rank IN 1..3 LOOP
   SELECT sum(pink_count) INTO v_total FROM public.lootzy_bonus_entries WHERE game_id=v_game AND rank IS NULL;
   v_ticket := random()*v_total;
   SELECT telegram_id INTO v_id FROM (
     SELECT telegram_id,sum(pink_count) OVER (ORDER BY telegram_id) AS cumulative FROM public.lootzy_bonus_entries WHERE game_id=v_game AND rank IS NULL
   ) weighted WHERE cumulative>v_ticket ORDER BY cumulative LIMIT 1;
   UPDATE public.lootzy_bonus_entries SET rank=v_rank WHERE game_id=v_game AND telegram_id=v_id;
   v_qty := CASE v_rank WHEN 1 THEN 10 WHEN 2 THEN 3 ELSE 5 END;
   v_color := CASE WHEN v_rank<3 THEN 'pink' ELSE 'green' END;
   UPDATE public.lootzy_accounts SET pink=pink+CASE WHEN v_color='pink' THEN v_qty ELSE 0 END,green=green+CASE WHEN v_color='green' THEN v_qty ELSE 0 END,updated_at=now() WHERE telegram_id=v_id;
   INSERT INTO public.lootzy_events(id,telegram_id,actor_id,kind,color,quantity,verified) VALUES(gen_random_uuid(),v_id,p_actor,'grant',v_color,v_qty,true);
 END LOOP;
 UPDATE public.lootzy_bonus_games SET drawn_at=now(),drawn_by=p_actor WHERE id=v_game;
 RETURN jsonb_build_object('drawn',true,'replayed',false);
END $$;
REVOKE ALL ON FUNCTION public.lootzy_bonus_manage(bigint,text,bigint,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lootzy_bonus_manage(bigint,text,bigint,integer) TO service_role;