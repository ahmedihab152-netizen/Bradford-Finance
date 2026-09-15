import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

const corsHeaders = {
  "access-control-allow-origin": "*",
  "access-control-allow-headers": "authorization, x-client-info, apikey, content-type",
  "access-control-allow-methods": "POST, OPTIONS",
  "cache-control": "no-store",
  "content-type": "application/json",
};

Deno.serve(async req=>{
 if(req.method==="OPTIONS")return new Response(null,{status:204,headers:corsHeaders});
 if(req.method!=="POST")return new Response(JSON.stringify({error:"POST required"}),{status:405,headers:corsHeaders});
 const auth=req.headers.get("authorization");if(!auth)return new Response(JSON.stringify({error:"Authentication required"}),{status:401,headers:corsHeaders});
 try{const {document_id}=await req.json();if(!document_id)return new Response(JSON.stringify({error:"document_id required"}),{status:400,headers:corsHeaders});const client=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_ANON_KEY")!,{global:{headers:{Authorization:auth}}});const {data,error}=await client.rpc("tax_process_sandbox",{p_document:document_id});if(error)throw error;return new Response(JSON.stringify(data),{headers:corsHeaders})}catch(e){return new Response(JSON.stringify({error:e instanceof Error?e.message:"Request failed"}),{status:400,headers:corsHeaders})}
});
