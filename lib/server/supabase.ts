import {createClient} from "@supabase/supabase-js";
const url=process.env.NEXT_PUBLIC_SUPABASE_URL;
const key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
export function createPublicDb(){
 if(!url||!key)throw new Error("Supabase public connection is not configured");
 return createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
}
export async function requireUser(request:Request){
 const token=(request.headers.get("authorization")||"").match(/^Bearer\s+(.+)$/i)?.[1];
 if(!token)throw Object.assign(new Error("로그인이 필요합니다."),{status:401});
 const db=createClient(url!,key!,{global:{headers:{Authorization:"Bearer "+token}},auth:{persistSession:false,autoRefreshToken:false}});
 const {data,error}=await db.auth.getUser(token);
 if(error||!data.user)throw Object.assign(new Error("유효하지 않은 로그인 정보입니다."),{status:401});
 return {db,user:data.user};
}
