import {redirect} from "next/navigation";
export default async function OfficialRaceResultRedirect({params}){
 const {id}=await params;
 redirect("/race/"+encodeURIComponent(id));
}
