import {NextResponse} from "next/server";
import {requireUser} from "../../../../lib/server/supabase";
export const dynamic="force-dynamic";
export const runtime="nodejs";
export async function GET(req:Request){
 try{const {db}=await requireUser(req);
  const {data,error}=await db.schema("my_derby").rpc("player_finance_dashboard");
  if(error)throw error;
  return NextResponse.json(data,{headers:{"Cache-Control":"no-store"}});
 }catch(e){return NextResponse.json({error:(e as Error).message},{status:400})}
}

export async function POST(req:Request){
 try{
  const {db}=await requireUser(req);
  const body=await req.json();
  if(!body||Object.keys(body).join(",")!=="action"||body.action!=="RECOVER")
   return NextResponse.json({error:"올바른 회생 신청이 아닙니다."},{status:400});
  const {data,error}=await db.schema("my_derby").rpc("player_financial_recovery");
  if(error)throw error;
  return NextResponse.json(data);
 }catch(e){return NextResponse.json({error:(e as Error).message},{status:400})}
}
