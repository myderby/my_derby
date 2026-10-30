"use client";
const idPattern=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function staffProfileHref({kind,staffId}={}){
 if(!idPattern.test(String(staffId||"")))return null;
 if(kind!=="jockey"&&kind!=="trainer")return null;
 return "/"+(kind==="jockey"?"jockeys":"trainers")+"/"+encodeURIComponent(staffId);
}
export default function StaffLink({kind,staffId,children,className,style,title}){
 const href=staffProfileHref({kind,staffId});
 if(!href)return <span className={className} style={style}>{children}</span>;
 return <a href={href} className={className} style={{color:"inherit",textDecoration:"underline",textDecorationColor:"#91734c",textUnderlineOffset:3,...style}} title={title||(kind==="jockey"?"기수":"조교사")+" 상세정보 보기"} onClick={event=>event.stopPropagation()}>{children}</a>;
}
