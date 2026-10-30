import StaffProfile from "../../components/StaffProfile";
export const dynamic="force-dynamic";
export default async function TrainerProfile({params}){
 const {id}=await params;
 return <StaffProfile kind="trainer" id={id}/>;
}
