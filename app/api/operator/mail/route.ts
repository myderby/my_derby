import {NextResponse} from "next/server";
import {requireUser} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
const uuid=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;
const operator=(user:any)=>["operator","admin"].includes(user?.app_metadata?.role);
export async function GET(req:Request){
 try{
  const {db,user}=await requireUser(req);if(!operator(user))return NextResponse.json({error:"운영자 권한이 필요합니다."},{status:403});
  const search=new URL(req.url).searchParams.get("search")||"";
  if(search.length>40)return NextResponse.json({error:"검색어는 40자 이내로 입력해주세요."},{status:400});
  const {data,error}=await db.schema("my_derby").rpc("operator_mail_recipients",{p_search:search});
  if(error)throw error;return NextResponse.json({recipients:data||[]},{headers:{"Cache-Control":"no-store"}});
 }catch(e){const x=e as {status?:number;message?:string};return NextResponse.json({error:x.message||"수신자 조회 실패"},{status:x.status||400});}
}
export async function POST(req:Request){
 try{
  const {db,user}=await requireUser(req);if(!operator(user))return NextResponse.json({error:"운영자 권한이 필요합니다."},{status:403});
  const body=await req.json();
  if(!body||typeof body!=="object"||Array.isArray(body)||
   Object.keys(body).sort().join(",")!=="itemCode,itemDescription,itemName,message,quantity,userId"||
   !uuid.test(body.userId)||typeof body.itemCode!=="string"||! /^[A-Z0-9_]{2,40}$/.test(body.itemCode)||
   typeof body.itemName!=="string"||body.itemName.trim().length<1||body.itemName.length>60||
   typeof body.itemDescription!=="string"||body.itemDescription.length>160||
   !Number.isInteger(body.quantity)||body.quantity<1||body.quantity>99||
   typeof body.message!=="string"||body.message.length>300)
   return NextResponse.json({error:"선물 정보와 수신자를 확인해주세요."},{status:400});
  const {data,error}=await db.schema("my_derby").rpc("operator_send_gift",{
   p_user_id:body.userId,p_item_code:body.itemCode,p_item_name:body.itemName.trim(),
   p_item_description:body.itemDescription,p_quantity:body.quantity,p_message:body.message});
  if(error)throw error;return NextResponse.json(data);
 }catch(e){const x=e as {status?:number;message?:string};return NextResponse.json({error:x.message||"선물을 보내지 못했습니다."},{status:x.status||400});}
}
