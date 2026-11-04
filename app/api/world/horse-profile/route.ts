import {NextResponse} from "next/server";
import {createPublicDb,requireUser} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export async function GET(req:Request){
 const q=new URL(req.url).searchParams;
 const horseId=q.get("horseId");
 const meet=q.get("meet");
 const hrNo=q.get("hrNo");
 const byHorse=horseId!==null;
 if((byHorse&&!uuid.test(horseId||""))||
   (!byHorse&&(!["서울","영남","제주"].includes(meet||"")||
   !/^[0-9a-z]{1,24}$/i.test(hrNo||""))))
   return NextResponse.json({error:"경주마 식별정보가 올바르지 않습니다."},{status:400});
 try{
  const authenticated=!!req.headers.get("authorization");
  const db=authenticated? (await requireUser(req)).db:createPublicDb();
  const {data,error}=await db.schema("my_derby")
   .rpc("world_horse_profile",{
    p_horse_id:byHorse?horseId:null,
    p_source_meet:byHorse?null:meet,
    p_source_hr_no:byHorse?null:hrNo
   });
  if(error)throw error;
  if(!data||data.status==="NOT_FOUND")
   return NextResponse.json({error:"해당 경주마 정보가 없습니다."},{status:404});
  if(byHorse&&data.gameHorseId&&["MALE","FEMALE"].includes(data.sex)){
   const {data:offspring,error:offspringError}=await db.schema("my_derby")
    .rpc("world_horse_offspring_profile",{p_horse_id:horseId,p_page:1,p_page_size:20});
   if(!offspringError&&offspring?.status==="OK")data.offspring=offspring;
  }
  if(authenticated&&byHorse){
   const {data:genetics,error:geneticsError}=await db.schema("my_derby")
    .rpc("player_horse_genetic_discovery",{p_horse_id:horseId});
   if(!geneticsError)data.genetics=genetics;
  }
  return NextResponse.json(data,{headers:{"Cache-Control":"no-store"}});
 }catch(e){
  console.error("horse profile lookup failed",e instanceof Error?e.message:"unknown");
  return NextResponse.json({error:"경주마 상세정보를 불러오지 못했습니다."},{status:503});
 }
}
