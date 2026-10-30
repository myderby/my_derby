import {NextResponse} from "next/server";
import {createPublicDb} from "../../../../lib/server/supabase";
export const dynamic="force-dynamic";
export async function GET(){try{const {data,error}=await createPublicDb().schema("my_derby").rpc("public_participant_directory");if(error)throw error;return NextResponse.json({people:data||[]},{headers:{"Cache-Control":"no-store"}})}catch(e){return NextResponse.json({error:e.message},{status:503})}}
