import { createClient } from '@supabase/supabase-js'
import { caserneReponse } from './texte.js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

if (!supabaseUrl || !supabaseAnonKey) {
  throw new Error(
    'Configuration Supabase manquante : renseigner VITE_SUPABASE_URL et VITE_SUPABASE_ANON_KEY dans .env'
  )
}

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: { flowType: 'pkce' },
})

// Les fonctions du serveur écrivent encore « dortoir » dans leurs messages : on les traduit en « caserne ».
const rpcOrigine = supabase.rpc.bind(supabase)
supabase.rpc = (...args) => rpcOrigine(...args).then(caserneReponse)
