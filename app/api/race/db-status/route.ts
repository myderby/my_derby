import {NextResponse} from "next/server";
import {createPublicDb} from "../../../../lib/server/supabase";
export const dynamic="force-dynamic";
export async function GET(){
 try{
  const db=createPublicDb().schema("my_derby");
  const [races,fixtures]=await Promise.all([
   db.from("races").select("id",{count:"exact",head:true}),
   db.from("race_test_fixtures").select("slot",{count:"exact",head:true}),
  ]);
  if(races.error||fixtures.error)throw races.error||fixtures.error;
  return NextResponse.json({
   connected:true,schema:"my_derby",
   registeredRaces:races.count??0,
   storedTestFixtures:fixtures.count??0,
   officialRaceProcessingEnabled:false,
  },{headers:{"Cache-Control":"no-store"}});
 }catch(err){
  return NextResponse.json({connected:false,error:err instanceof Error?err.message:"Database is unavailable"},
   {status:503,headers:{"Cache-Control":"no-store"}});
 }
}
