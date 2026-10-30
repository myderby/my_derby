import StaffProfile from "../../components/StaffProfile";
export const dynamic="force-dynamic";
export default async function JockeyProfile({params}){
 const {id}=await params;
 return <StaffProfile kind="jockey" id={id}/>;
}
