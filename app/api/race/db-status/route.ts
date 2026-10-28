import {NextResponse} from "next/server";
import {createPublicDb} from "../../../../lib/server/supabase";
import {simulateRace} from "../../../../lib/racing/engine";
export const dynamic="force-dynamic";
export async function GET(request:Request){
 try{
  const db=createPublicDb().schema("my_derby");
  const [races,fixtures]=await Promise.all([
   db.from("races").select("id",{count:"exact",head:true}),
   db.from("race_test_fixtures").select("slot",{count:"exact",head:true}),
  ]);
  if(races.error||fixtures.error)throw races.error||fixtures.error;
  const smoke=new URL(request.url).searchParams.get("smoke")==="1";
  let sampleRun=null;
  if(smoke){
   const {data,error}=await db.from("race_test_fixtures").select("race_input").eq("slot",0).single();
   if(error||!data)throw error||new Error("Test fixture missing");
   const result=simulateRace(data.race_input);
   sampleRun={raceId:result.raceId,finishers:result.results.length,firstPlace:result.results[0].name,sections:result.sections.length,engineVersion:result.version};
  }
  return NextResponse.json({
   connected:true,schema:"my_derby",sampleRun,
   registeredRaces:races.count??0,
   storedTestFixtures:fixtures.count??0,
   officialRaceProcessingEnabled:false,
  },{headers:{"Cache-Control":"no-store"}});
 }catch(err){
  return NextResponse.json({connected:false,error:err instanceof Error?err.message:"Database is unavailable"},
   {status:503,headers:{"Cache-Control":"no-store"}});
 }
}
