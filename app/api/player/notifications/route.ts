import {NextResponse} from "next/server";
import {requireUser} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
export async function GET(req:Request){
 try{const {db}=await requireUser(req);
 const r=await db.schema("my_derby").rpc("player_inbox");
 if(r.error)throw r.error;
 return NextResponse.json(r.data,{headers:{"Cache-Control":"no-store"}});
 }catch(e){return NextResponse.json({error:(e as Error).message},{status:400})}
}
export async function POST(req:Request){
 try{const {db}=await requireUser(req);const body=await req.json();
 if(!body||typeof body!=="object"||Array.isArray(body))
  return NextResponse.json({error:"요청 내용을 확인해주세요."},{status:400});
 if(body.action==="CLAIM_GIFT"&&Object.keys(body).sort().join(",")==="action,giftId"&&
    Number.isSafeInteger(body.giftId)&&body.giftId>0){
  const r=await db.schema("my_derby").rpc("player_claim_gift",{p_gift_id:body.giftId});
  if(r.error)throw r.error;return NextResponse.json(r.data);
 }
 if(Object.keys(body).join(",")!=="id"||!Number.isSafeInteger(body.id)||body.id<=0)
  return NextResponse.json({error:"올바른 알림을 선택하세요."},{status:400});
 const r=await db.schema("my_derby").rpc("player_mark_notification_read",{p_id:body.id});
 if(r.error)throw r.error;return NextResponse.json(r.data);
 }catch(e){return NextResponse.json({error:(e as Error).message},{status:400})}
}
