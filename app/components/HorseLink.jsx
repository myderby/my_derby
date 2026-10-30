"use client";
export function horseProfileHref({horseId,sourceMeet,hrNo}={}){
 if(typeof horseId==="string"&&/^[0-9a-f]{8}-[0-9a-f-]{27,}$/i.test(horseId))
  return "/horses/profile?horseId="+encodeURIComponent(horseId);
 if(sourceMeet&&hrNo)
  return "/horses/profile?meet="+encodeURIComponent(sourceMeet)+
    "&hrNo="+encodeURIComponent(String(hrNo));
 return null;
}
export default function HorseLink({horseId,sourceMeet,hrNo,children,className,style,title}){
 const href=horseProfileHref({horseId,sourceMeet,hrNo});
 if(!href)return <span className={className} style={style}>{children}</span>;
 return <a href={href} className={className}
  style={{color:"inherit",textDecoration:"underline",textDecorationColor:"#91734c",
   textUnderlineOffset:3,...style}}
  title={title||"경주마 기본정보 보기"}
  onClick={e=>e.stopPropagation()}>{children}</a>;
}
