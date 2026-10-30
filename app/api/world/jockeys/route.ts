import {NextResponse} from "next/server";
import {createPublicDb} from "../../../../lib/server/supabase";
export const runtime="nodejs";
export const dynamic="force-dynamic";
const result=(data:unknown,status=200)=>NextResponse.json(data,{status,headers:{"Cache-Control":"no-store"}});
export async function GET(request:Request){
 try{
  const q=new URL(request.url).searchParams;
  const page=Number(q.get("page")??"1");
  const size=Number(q.get("size")??"24");
  const search=(q.get("q")||"").trim(),track=q.get("track")||null;
  const sort=q.get("sort")||"name";
  if(!Number.isInteger(page)||page<1||page>10000||
   !Number.isInteger(size)||size<1||size>50||
   search.length>50||!["name","rides","wins"].includes(sort)||
   (track!==null&&!["서울","부산","영천"].includes(track)))
   return result({error:"검색 조건이 올바르지 않습니다."},400);
  const {data,error}=await createPublicDb().schema("my_derby").rpc("world_jockey_directory",{
    p_search:search||null,p_track:track,p_page:page,p_page_size:size,p_sort:sort
  });
  if(error)throw error;
  return result(data);
 }catch(e){
  console.error("Jockey roster query error",e instanceof Error?e.message:"Unknown");
  return result({error:"기수 목록을 불러오지 못했습니다."},503);
 }
}