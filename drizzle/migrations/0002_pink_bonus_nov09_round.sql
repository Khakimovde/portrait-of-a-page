CREATE OR REPLACE FUNCTION public.lootzy_bonus_nov09_manage(p_actor bigint, p_action text, p_target bigint DEFAULT NULL, p_quantity integer DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
 v_game text := 'pink-2026-11-09'; v_drawn timestamptz; v_id bigint; v_rank integer; v_total bigint; v_ticket double precision; v_qty integer;
BEGIN
 IF NOT EXISTS (SELECT 1 FROM public.lootzy_roles WHERE telegram_id=p_actor AND role='admin') THEN RAISE EXCEPTION 'Admin uchun ruxsat yo‘q'; END IF;
 IF p_action NOT IN ('add','draw') OR p_action IS NULL THEN RAISE EXCEPTION 'Noto‘g‘ri amal'; END IF;
 PERFORM pg_advisory_xact_lock(911202623);
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
 IF now() < '2026-11-09 23:00:00+05'::timestamptz THEN RAISE EXCEPTION 'O‘yin 09.11.2026 soat 23:00 (Toshkent) dan keyin boshlanadi'; END IF;
 IF (SELECT count(*) FROM public.lootzy_bonus_entries WHERE game_id=v_game) < 3 THEN RAISE EXCEPTION 'Kamida 3 ta ishtirokchi kerak'; END IF;
 FOR v_rank IN 1..3 LOOP
   SELECT sum(pink_count) INTO v_total FROM public.lootzy_bonus_entries WHERE game_id=v_game AND rank IS NULL;
   v_ticket := random()*v_total;
   SELECT telegram_id INTO v_id FROM (
     SELECT telegram_id,sum(pink_count) OVER (ORDER BY telegram_id) AS cumulative FROM public.lootzy_bonus_entries WHERE game_id=v_game AND rank IS NULL
   ) weighted WHERE cumulative>v_ticket ORDER BY cumulative LIMIT 1;
   UPDATE public.lootzy_bonus_entries SET rank=v_rank WHERE game_id=v_game AND telegram_id=v_id;
   v_qty := CASE v_rank WHEN 1 THEN 15 WHEN 2 THEN 10 ELSE 5 END;
   UPDATE public.lootzy_accounts SET pink=pink+v_qty,updated_at=now() WHERE telegram_id=v_id;
   INSERT INTO public.lootzy_events(id,telegram_id,actor_id,kind,color,quantity,verified) VALUES(gen_random_uuid(),v_id,p_actor,'grant','pink',v_qty,true);
 END LOOP;
 UPDATE public.lootzy_bonus_games SET drawn_at=now(),drawn_by=p_actor WHERE id=v_game;
 RETURN jsonb_build_object('drawn',true,'replayed',false);
END $$;
REVOKE ALL ON FUNCTION public.lootzy_bonus_nov09_manage(bigint,text,bigint,integer) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.lootzy_bonus_nov09_manage(bigint,text,bigint,integer) TO service_role;
COMMENT ON FUNCTION public.lootzy_bonus_nov09_manage(bigint,text,bigint,integer) IS 'November 9 independent Pink round; previous rounds and payouts remain unchanged.';