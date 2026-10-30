import {NextResponse} from "next/server";
import {createPublicDb} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
const result=(data:unknown,status=200)=>NextResponse.json(data,{status,headers:{"Cache-Control":"no-store"}});
export async function GET(request:Request){
 try{
  const q=new URL(request.url).searchParams;
  const rawPage=q.get("page")??"1",rawSize=q.get("size")??"24";
  const page=Number(rawPage),size=Number(rawSize);
  const gradeRaw=q.get("grade");
  const grade=gradeRaw===null||gradeRaw===""?null:Number(gradeRaw);
  const search=(q.get("q")||"").trim();
  const track=q.get("track")||null,sex=q.get("sex")||null,
   stage=q.get("stage")||null,sort=q.get("sort")||"name";
  if(!Number.isInteger(page)||page<1||page>10000||
   !Number.isInteger(size)||size<1||size>50||
   (grade!==null&&(!Number.isInteger(grade)||grade<1||grade>6))||
   search.length>50||!["name","rating","age","grade"].includes(sort)||
   (track!==null&&!["서울","부산","영천","제주"].includes(track))||
   (sex!==null&&!["MALE","FEMALE","GELDING"].includes(sex))||
   (stage!==null&&!["RACING","RETIRED","FOAL","YEARLING","STALLION","BROODMARE","DECEASED"].includes(stage)))
   return result({error:"검색 조건이 올바르지 않습니다."},400);
  const {data,error}=await createPublicDb().schema("my_derby").rpc("world_horse_directory",{
    p_search:search||null,p_track:track,p_grade:grade,p_sex:sex,
    p_stage:stage,p_page:page,p_page_size:size,p_sort:sort
  });
  if(error)throw error;
  return result(data);
 }catch(e){
  console.error("Horse roster query error",e instanceof Error?e.message:"Unknown");
  return result({error:"경주마 목록을 불러오지 못했습니다."},503);
 }
}