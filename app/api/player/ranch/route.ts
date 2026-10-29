import {NextResponse} from "next/server";
import {requireUser} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
const uuid=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i;
const courses=["REST_3D","RECOVERY_7D","REHAB","YOUNG_BASIC"];
export async function GET(req:Request){
 try{const {db}=await requireUser(req);const r=await db.schema("my_derby").rpc("player_ranch_board");
 if(r.error)throw r.error;return NextResponse.json(r.data,{headers:{"Cache-Control":"no-store"}});
 }catch(e){return NextResponse.json({error:(e as Error).message},{status:400})}
}
export async function POST(req:Request){
 try{const {db}=await requireUser(req);const b=await req.json();
 if(!b||Object.keys(b).sort().join(",")!=="course,horseId"||!uuid.test(b.horseId)||!courses.includes(b.course))
  return NextResponse.json({error:"올바른 목장 코스와 경주마를 선택하세요."},{status:400});
 const r=await db.schema("my_derby").rpc("player_ranch_apply",
  {p_horse:b.horseId,p_course:b.course});
 if(r.error)throw r.error;return NextResponse.json(r.data);
 }catch(e){return NextResponse.json({error:(e as Error).message},{status:400})}
}
