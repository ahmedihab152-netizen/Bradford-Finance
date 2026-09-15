import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
Deno.serve(async req=>{
 if(req.method!=="POST")return new Response(JSON.stringify({error:"POST required"}),{status:405,headers:{"content-type":"application/json"}});
 const auth=req.headers.get("authorization");if(!auth)return new Response(JSON.stringify({error:"Authentication required"}),{status:401,headers:{"content-type":"application/json"}});
 try{const {document_id}=await req.json();if(!document_id)return new Response(JSON.stringify({error:"document_id required"}),{status:400,headers:{"content-type":"application/json"}});const client=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_ANON_KEY")!,{global:{headers:{Authorization:auth}}});const {data,error}=await client.rpc("tax_process_sandbox",{p_document:document_id});if(error)throw error;return new Response(JSON.stringify(data),{headers:{"content-type":"application/json","cache-control":"no-store"}})}catch(e){return new Response(JSON.stringify({error:e instanceof Error?e.message:"Request failed"}),{status:400,headers:{"content-type":"application/json","cache-control":"no-store"}})}
});
