
CREATE OR REPLACE FUNCTION my_derby.player_inbox()
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $fn$
 SELECT CASE WHEN auth.uid() IS NULL THEN
  jsonb_build_object('error','LOGIN_REQUIRED')
 ELSE jsonb_build_object(
  'unread',(SELECT count(*) FROM my_derby.notifications n
    WHERE n.owner_user_id=auth.uid() AND n.read_at IS NULL),
  'items',coalesce((SELECT jsonb_agg(x.item ORDER BY x.id DESC) FROM (
    SELECT n.id,jsonb_build_object('id',n.id,'category',n.category,
    'title',n.title,'body',n.body,'createdAt',n.created_at,
    'readAt',n.read_at,'payload',n.payload) item
    FROM my_derby.notifications n WHERE n.owner_user_id=auth.uid()
    ORDER BY n.id DESC LIMIT 100) x),'[]'::jsonb))
 END;
$fn$;
CREATE OR REPLACE FUNCTION my_derby.player_mark_notification_read(p_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $fn$
DECLARE u uuid:=auth.uid();v_read bigint;
BEGIN
 IF u IS NULL THEN RAISE EXCEPTION 'LOGIN_REQUIRED' USING ERRCODE='42501';END IF;
 UPDATE my_derby.notifications SET read_at=coalesce(read_at,now())
 WHERE id=p_id AND owner_user_id=u RETURNING id INTO v_read;
 IF v_read IS NULL THEN RAISE EXCEPTION 'NOTIFICATION_NOT_OWNED' USING ERRCODE='42501';END IF;
 RETURN jsonb_build_object('status','READ','id',v_read);
END $fn$;
REVOKE ALL ON FUNCTION my_derby.player_inbox() FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION my_derby.player_mark_notification_read(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_inbox() TO authenticated;
GRANT EXECUTE ON FUNCTION my_derby.player_mark_notification_read(bigint) TO authenticated;
