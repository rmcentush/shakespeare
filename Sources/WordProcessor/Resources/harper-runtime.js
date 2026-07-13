"use strict";(()=>{var pe=Object.create;var Mn=Object.defineProperty;var we=Object.getOwnPropertyDescriptor;var be=Object.getOwnPropertyNames;var me=Object.getPrototypeOf,ye=Object.prototype.hasOwnProperty;var he=(r=>typeof require<"u"?require:typeof Proxy<"u"?new Proxy(r,{get:(n,e)=>(typeof require<"u"?require:n)[e]}):r)(function(r){if(typeof require<"u")return require.apply(this,arguments);throw Error('Dynamic require of "'+r+'" is not supported')});var ve=(r,n,e,t)=>{if(n&&typeof n=="object"||typeof n=="function")for(let i of be(n))!ye.call(r,i)&&i!==e&&Mn(r,i,{get:()=>n[i],enumerable:!(t=we(n,i))||t.enumerable});return r};var Se=(r,n,e)=>(e=r!=null?pe(me(r)):{},ve(n||!r||!r.__esModule?Mn(e,"default",{value:r,enumerable:!0}):e,r));var $e=Object.defineProperty,Hn=r=>{throw TypeError(r)},je=(r,n,e)=>n in r?$e(r,n,{enumerable:!0,configurable:!0,writable:!0,value:e}):r[n]=e,bn=(r,n,e)=>je(r,typeof n!="symbol"?n+"":n,e),Kn=(r,n,e)=>n.has(r)||Hn("Cannot "+e),T=(r,n,e)=>(Kn(r,n,"read from private field"),e?e.call(r):n.get(r)),kn=(r,n,e)=>n.has(r)?Hn("Cannot add the same private member more than once"):n instanceof WeakSet?n.add(r):n.set(r,e),tn=(r,n,e,t)=>(Kn(r,n,"write to private field"),t?t.call(r,e):n.set(r,e),e),U,S,N=Object.freeze({American:0,0:"American",British:1,1:"British",Australian:2,2:"Australian",Canadian:3,3:"Canadian",Indian:4,4:"Indian"}),W=Object.freeze({Plain:0,0:"Plain",Markdown:1,1:"Markdown",Typst:2,2:"Typst"}),z=class rn{static __wrap(n){let e=Object.create(rn.prototype);return e.__wbg_ptr=n,zn.register(e,e.__wbg_ptr,e),e}static __unwrap(n){return n instanceof rn?n.__destroy_into_raw():0}__destroy_into_raw(){let n=this.__wbg_ptr;return this.__wbg_ptr=0,zn.unregister(this),n}free(){let n=this.__destroy_into_raw();s.__wbg_lint_free(n,0)}static from_json(n){let e=m(n,s.__wbindgen_malloc,s.__wbindgen_realloc),t=d,i=s.lint_from_json(e,t);if(i[2])throw j(i[1]);return rn.__wrap(i[0])}get_problem_text(){let n,e;try{let t=s.lint_get_problem_text(this.__wbg_ptr);return n=t[0],e=t[1],f(t[0],t[1])}finally{s.__wbindgen_free(n,e,1)}}lint_kind(){let n,e;try{let t=s.lint_lint_kind(this.__wbg_ptr);return n=t[0],e=t[1],f(t[0],t[1])}finally{s.__wbindgen_free(n,e,1)}}lint_kind_pretty(){let n,e;try{let t=s.lint_lint_kind_pretty(this.__wbg_ptr);return n=t[0],e=t[1],f(t[0],t[1])}finally{s.__wbindgen_free(n,e,1)}}message(){let n,e;try{let t=s.lint_message(this.__wbg_ptr);return n=t[0],e=t[1],f(t[0],t[1])}finally{s.__wbindgen_free(n,e,1)}}message_html(){let n,e;try{let t=s.lint_message_html(this.__wbg_ptr);return n=t[0],e=t[1],f(t[0],t[1])}finally{s.__wbindgen_free(n,e,1)}}span(){let n=s.lint_span(this.__wbg_ptr);return cn.__wrap(n)}suggestion_count(){return s.lint_suggestion_count(this.__wbg_ptr)>>>0}suggestions(){let n=s.lint_suggestions(this.__wbg_ptr);var e=Q(n[0],n[1]).slice();return s.__wbindgen_free(n[0],n[1]*4,4),e}to_json(){let n,e;try{let t=s.lint_to_json(this.__wbg_ptr);return n=t[0],e=t[1],f(t[0],t[1])}finally{s.__wbindgen_free(n,e,1)}}};Symbol.dispose&&(z.prototype[Symbol.dispose]=z.prototype.free);var jn=class xn{static __wrap(n){let e=Object.create(xn.prototype);return e.__wbg_ptr=n,Rn.register(e,e.__wbg_ptr,e),e}__destroy_into_raw(){let n=this.__wbg_ptr;return this.__wbg_ptr=0,Rn.unregister(this),n}free(){let n=this.__destroy_into_raw();s.__wbg_linter_free(n,0)}apply_suggestion(n,e,t){let i,_;try{let c=m(n,s.__wbindgen_malloc,s.__wbindgen_realloc),b=d;mn(e,z),mn(t,nn);let g=s.linter_apply_suggestion(this.__wbg_ptr,c,b,e.__wbg_ptr,t.__wbg_ptr);var o=g[0],l=g[1];if(g[3])throw o=0,l=0,j(g[2]);return i=o,_=l,f(o,l)}finally{s.__wbindgen_free(i,_,1)}}clear_ignored_lints(){s.linter_clear_ignored_lints(this.__wbg_ptr)}clear_words(){s.linter_clear_words(this.__wbg_ptr)}context_hash(n,e){let t=m(n,s.__wbindgen_malloc,s.__wbindgen_realloc),i=d;mn(e,z);let _=s.linter_context_hash(this.__wbg_ptr,t,i,e.__wbg_ptr);return BigInt.asUintN(64,_)}export_ignored_lints(){let n,e;try{let t=s.linter_export_ignored_lints(this.__wbg_ptr);return n=t[0],e=t[1],f(t[0],t[1])}finally{s.__wbindgen_free(n,e,1)}}export_words(){let n=s.linter_export_words(this.__wbg_ptr);var e=Q(n[0],n[1]).slice();return s.__wbindgen_free(n[0],n[1]*4,4),e}generate_stats_file(){let n,e;try{let t=s.linter_generate_stats_file(this.__wbg_ptr);return n=t[0],e=t[1],f(t[0],t[1])}finally{s.__wbindgen_free(n,e,1)}}get_dialect(){return s.linter_get_dialect(this.__wbg_ptr)}get_lint_config_as_json(){let n,e;try{let t=s.linter_get_lint_config_as_json(this.__wbg_ptr);return n=t[0],e=t[1],f(t[0],t[1])}finally{s.__wbindgen_free(n,e,1)}}get_lint_config_as_object(){return s.linter_get_lint_config_as_object(this.__wbg_ptr)}get_lint_descriptions_as_json(){let n,e;try{let t=s.linter_get_lint_descriptions_as_json(this.__wbg_ptr);return n=t[0],e=t[1],f(t[0],t[1])}finally{s.__wbindgen_free(n,e,1)}}get_lint_descriptions_as_object(){return s.linter_get_lint_descriptions_as_object(this.__wbg_ptr)}get_lint_descriptions_html_as_json(){let n,e;try{let t=s.linter_get_lint_descriptions_html_as_json(this.__wbg_ptr);return n=t[0],e=t[1],f(t[0],t[1])}finally{s.__wbindgen_free(n,e,1)}}get_lint_descriptions_html_as_object(){return s.linter_get_lint_descriptions_html_as_object(this.__wbg_ptr)}get_structured_lint_config_as_json(){let n,e;try{let t=s.linter_get_structured_lint_config_as_json(this.__wbg_ptr);return n=t[0],e=t[1],f(t[0],t[1])}finally{s.__wbindgen_free(n,e,1)}}get_structured_lint_config_as_object(){return s.linter_get_structured_lint_config_as_object(this.__wbg_ptr)}ignore_hashes(n){let e=Ee(n,s.__wbindgen_malloc),t=d;s.linter_ignore_hashes(this.__wbg_ptr,e,t)}ignore_lints(n,e){let t=m(n,s.__wbindgen_malloc,s.__wbindgen_realloc),i=d,_=Wn(e,s.__wbindgen_malloc),o=d;s.linter_ignore_lints(this.__wbg_ptr,t,i,_,o)}import_ignored_lints(n){let e=m(n,s.__wbindgen_malloc,s.__wbindgen_realloc),t=d,i=s.linter_import_ignored_lints(this.__wbg_ptr,e,t);if(i[1])throw j(i[0])}import_stats_file(n){let e=m(n,s.__wbindgen_malloc,s.__wbindgen_realloc),t=d,i=s.linter_import_stats_file(this.__wbg_ptr,e,t);if(i[1])throw j(i[0])}import_weirpack(n){let e=Oe(n,s.__wbindgen_malloc),t=d,i=s.linter_import_weirpack(this.__wbg_ptr,e,t);if(i[2])throw j(i[1]);return j(i[0])}import_words(n){let e=Wn(n,s.__wbindgen_malloc),t=d;s.linter_import_words(this.__wbg_ptr,e,t)}is_likely_english(n){let e=m(n,s.__wbindgen_malloc,s.__wbindgen_realloc),t=d;return s.linter_is_likely_english(this.__wbg_ptr,e,t)!==0}isolate_english(n){let e,t;try{let i=m(n,s.__wbindgen_malloc,s.__wbindgen_realloc),_=d,o=s.linter_isolate_english(this.__wbg_ptr,i,_);return e=o[0],t=o[1],f(o[0],o[1])}finally{s.__wbindgen_free(e,t,1)}}lint(n,e,t,i,_){let o=m(n,s.__wbindgen_malloc,s.__wbindgen_realloc),l=d;var c=A(i)?0:m(i,s.__wbindgen_malloc,s.__wbindgen_realloc),b=d;let g=s.linter_lint(this.__wbg_ptr,o,l,e,t,c,b,_);var F=Q(g[0],g[1]).slice();return s.__wbindgen_free(g[0],g[1]*4,4),F}static new(n){let e=s.linter_new(n);return xn.__wrap(e)}organized_lints(n,e,t,i,_){let o=m(n,s.__wbindgen_malloc,s.__wbindgen_realloc),l=d;var c=A(i)?0:m(i,s.__wbindgen_malloc,s.__wbindgen_realloc),b=d;let g=s.linter_organized_lints(this.__wbg_ptr,o,l,e,t,c,b,_);var F=Q(g[0],g[1]).slice();return s.__wbindgen_free(g[0],g[1]*4,4),F}set_lint_config_from_json(n){let e=m(n,s.__wbindgen_malloc,s.__wbindgen_realloc),t=d,i=s.linter_set_lint_config_from_json(this.__wbg_ptr,e,t);if(i[1])throw j(i[0])}set_lint_config_from_object(n){let e=s.linter_set_lint_config_from_object(this.__wbg_ptr,n);if(e[1])throw j(e[0])}summarize_stats(n,e){return s.linter_summarize_stats(this.__wbg_ptr,!A(n),A(n)?BigInt(0):n,!A(e),A(e)?BigInt(0):e)}};Symbol.dispose&&(jn.prototype[Symbol.dispose]=jn.prototype.free);var ln=class Qn{static __wrap(n){let e=Object.create(Qn.prototype);return e.__wbg_ptr=n,Nn.register(e,e.__wbg_ptr,e),e}__destroy_into_raw(){let n=this.__wbg_ptr;return this.__wbg_ptr=0,Nn.unregister(this),n}free(){let n=this.__destroy_into_raw();s.__wbg_organizedgroup_free(n,0)}get group(){let n,e;try{let t=s.__wbg_get_organizedgroup_group(this.__wbg_ptr);return n=t[0],e=t[1],f(t[0],t[1])}finally{s.__wbindgen_free(n,e,1)}}get lints(){let n=s.__wbg_get_organizedgroup_lints(this.__wbg_ptr);var e=Q(n[0],n[1]).slice();return s.__wbindgen_free(n[0],n[1]*4,4),e}set group(n){let e=m(n,s.__wbindgen_malloc,s.__wbindgen_realloc),t=d;s.__wbg_set_organizedgroup_group(this.__wbg_ptr,e,t)}set lints(n){let e=Wn(n,s.__wbindgen_malloc),t=d;s.__wbg_set_organizedgroup_lints(this.__wbg_ptr,e,t)}};Symbol.dispose&&(ln.prototype[Symbol.dispose]=ln.prototype.free);var cn=class sn{static __wrap(n){let e=Object.create(sn.prototype);return e.__wbg_ptr=n,Cn.register(e,e.__wbg_ptr,e),e}__destroy_into_raw(){let n=this.__wbg_ptr;return this.__wbg_ptr=0,Cn.unregister(this),n}free(){let n=this.__destroy_into_raw();s.__wbg_span_free(n,0)}get end(){return s.__wbg_get_span_end(this.__wbg_ptr)>>>0}get start(){return s.__wbg_get_span_start(this.__wbg_ptr)>>>0}set end(n){s.__wbg_set_span_end(this.__wbg_ptr,n)}set start(n){s.__wbg_set_span_start(this.__wbg_ptr,n)}static from_json(n){let e=m(n,s.__wbindgen_malloc,s.__wbindgen_realloc),t=d,i=s.span_from_json(e,t);if(i[2])throw j(i[1]);return sn.__wrap(i[0])}is_empty(){return s.span_is_empty(this.__wbg_ptr)!==0}len(){return s.span_len(this.__wbg_ptr)>>>0}static new(n,e){let t=s.span_new(n,e);return sn.__wrap(t)}to_json(){let n,e;try{let t=s.span_to_json(this.__wbg_ptr);return n=t[0],e=t[1],f(t[0],t[1])}finally{s.__wbindgen_free(n,e,1)}}};Symbol.dispose&&(cn.prototype[Symbol.dispose]=cn.prototype.free);var nn=class An{static __wrap(n){let e=Object.create(An.prototype);return e.__wbg_ptr=n,Dn.register(e,e.__wbg_ptr,e),e}__destroy_into_raw(){let n=this.__wbg_ptr;return this.__wbg_ptr=0,Dn.unregister(this),n}free(){let n=this.__destroy_into_raw();s.__wbg_suggestion_free(n,0)}static from_json(n){let e=m(n,s.__wbindgen_malloc,s.__wbindgen_realloc),t=d,i=s.suggestion_from_json(e,t);if(i[2])throw j(i[1]);return An.__wrap(i[0])}get_replacement_text(){let n,e;try{let t=s.suggestion_get_replacement_text(this.__wbg_ptr);return n=t[0],e=t[1],f(t[0],t[1])}finally{s.__wbindgen_free(n,e,1)}}kind(){return s.suggestion_kind(this.__wbg_ptr)}to_json(){let n,e;try{let t=s.suggestion_to_json(this.__wbg_ptr);return n=t[0],e=t[1],f(t[0],t[1])}finally{s.__wbindgen_free(n,e,1)}}};Symbol.dispose&&(nn.prototype[Symbol.dispose]=nn.prototype.free);var Yn=Object.freeze({Replace:0,0:"Replace",Remove:1,1:"Remove",InsertAfter:2,2:"InsertAfter"});function xe(){return s.get_default_lint_config()}function Ae(){let r,n;try{let e=s.get_default_lint_config_as_json();return r=e[0],n=e[1],f(e[0],e[1])}finally{s.__wbindgen_free(r,n,1)}}function Le(){s.setup()}function We(r){let n,e;try{let t=m(r,s.__wbindgen_malloc,s.__wbindgen_realloc),i=d,_=s.to_title_case(t,i);return n=_[0],e=_[1],f(_[0],_[1])}finally{s.__wbindgen_free(n,e,1)}}function Xn(){return{__proto__:null,"./harper_wasm_slim_bg.js":{__proto__:null,__wbg_Error_bce6d499ff0a4aff:function(n,e){return Error(f(n,e))},__wbg_String_8564e559799eccda:function(n,e){let t=String(e),i=m(t,s.__wbindgen_malloc,s.__wbindgen_realloc),_=d;h().setInt32(n+4,_,!0),h().setInt32(n+0,i,!0)},__wbg___wbindgen_boolean_get_2304fb8c853028c8:function(n){let e=n,t=typeof e=="boolean"?e:void 0;return A(t)?16777215:t?1:0},__wbg___wbindgen_debug_string_edece8177ad01481:function(n,e){let t=Ln(e),i=m(t,s.__wbindgen_malloc,s.__wbindgen_realloc),_=d;h().setInt32(n+4,_,!0),h().setInt32(n+0,i,!0)},__wbg___wbindgen_is_function_5cd60d5cf78b4eef:function(n){return typeof n=="function"},__wbg___wbindgen_is_object_b4593df85baada48:function(n){let e=n;return typeof e=="object"&&e!==null},__wbg___wbindgen_is_string_dde0fd9020db4434:function(n){return typeof n=="string"},__wbg___wbindgen_jsval_loose_eq_0ad77b7717db155c:function(n,e){return n==e},__wbg___wbindgen_number_get_f73a1244370fcc2c:function(n,e){let t=e,i=typeof t=="number"?t:void 0;h().setFloat64(n+8,A(i)?0:i,!0),h().setInt32(n+0,!A(i),!0)},__wbg___wbindgen_string_get_d109740c0d18f4d7:function(n,e){let t=e,i=typeof t=="string"?t:void 0;var _=A(i)?0:m(i,s.__wbindgen_malloc,s.__wbindgen_realloc),o=d;h().setInt32(n+4,o,!0),h().setInt32(n+0,_,!0)},__wbg___wbindgen_throw_9c31b086c2b26051:function(n,e){throw new Error(f(n,e))},__wbg_call_13665d9f14390edc:function(){return C(function(n,e){return n.call(e)},arguments)},__wbg_done_54b8da57023b7ed2:function(n){return n.done},__wbg_entries_564a7e8b1e54ede5:function(n){return Object.entries(n)},__wbg_error_a6fa202b58aa1cd3:function(n,e){let t,i;try{t=n,i=e,console.error(f(n,e))}finally{s.__wbindgen_free(t,i,1)}},__wbg_getRandomValues_3f44b700395062e5:function(){return C(function(n,e){globalThis.crypto.getRandomValues(yn(n,e))},arguments)},__wbg_getRandomValues_d49329ff89a07af1:function(){return C(function(n,e){globalThis.crypto.getRandomValues(yn(n,e))},arguments)},__wbg_getTime_09f1dd40a44edb30:function(n){return n.getTime()},__wbg_get_3e9a707ab7d352eb:function(){return C(function(n,e){return Reflect.get(n,e)},arguments)},__wbg_get_98fdf51d029a75eb:function(n,e){return n[e>>>0]},__wbg_get_unchecked_1dfe6d05ad91d9b7:function(n,e){return n[e>>>0]},__wbg_instanceof_ArrayBuffer_53db37b06f6b9afe:function(n){let e;try{e=n instanceof ArrayBuffer}catch{e=!1}return e},__wbg_instanceof_Uint8Array_abd07d4bd221d50b:function(n){let e;try{e=n instanceof Uint8Array}catch{e=!1}return e},__wbg_iterator_1441b47f341dc34f:function(){return Symbol.iterator},__wbg_length_2591a0f4f659a55c:function(n){return n.length},__wbg_length_56fcd3e2b7e0299d:function(n){return n.length},__wbg_lint_new:function(n){return z.__wrap(n)},__wbg_lint_unwrap:function(n){return z.__unwrap(n)},__wbg_log_0c201ade58bb55e1:function(n,e,t,i,_,o,l,c){let b,g;try{b=n,g=e,console.log(f(n,e),f(t,i),f(_,o),f(l,c))}finally{s.__wbindgen_free(b,g,1)}},__wbg_log_ce2c4456b290c5e7:function(n,e){let t,i;try{t=n,i=e,console.log(f(n,e))}finally{s.__wbindgen_free(t,i,1)}},__wbg_mark_b4d943f3bc2d2404:function(n,e){performance.mark(f(n,e))},__wbg_measure_84362959e621a2c1:function(){return C(function(n,e,t,i){let _,o,l,c;try{_=n,o=e,l=t,c=i,performance.measure(f(n,e),f(t,i))}finally{s.__wbindgen_free(_,o,1),s.__wbindgen_free(l,c,1)}},arguments)},__wbg_new_02d162bc6cf02f60:function(){return new Object},__wbg_new_070df68d66325372:function(){return new Map},__wbg_new_0_2722fcdb71a888a6:function(){return new Date},__wbg_new_227d7c05414eb861:function(){return new Error},__wbg_new_310879b66b6e95e1:function(){return new Array},__wbg_new_7ddec6de44ff8f5d:function(n){return new Uint8Array(n)},__wbg_next_2a4e19f4f5083b0f:function(n){return n.next},__wbg_next_6429a146bf756f93:function(){return C(function(n){return n.next()},arguments)},__wbg_organizedgroup_new:function(n){return ln.__wrap(n)},__wbg_prototypesetcall_5f9bdc8d75e07276:function(n,e,t){Uint8Array.prototype.set.call(yn(n,e),t)},__wbg_set_6be42768c690e380:function(n,e,t){n[e]=t},__wbg_set_78ea6a19f4818587:function(n,e,t){n[e>>>0]=t},__wbg_set_facb7a5914e0fa39:function(n,e,t){return n.set(e,t)},__wbg_stack_3b0d974bbf31e44f:function(n,e){let t=e.stack,i=m(t,s.__wbindgen_malloc,s.__wbindgen_realloc),_=d;h().setInt32(n+4,_,!0),h().setInt32(n+0,i,!0)},__wbg_suggestion_new:function(n){return nn.__wrap(n)},__wbg_value_9cc0518af87a489c:function(n){return n.value},__wbindgen_cast_0000000000000001:function(n){return n},__wbindgen_cast_0000000000000002:function(n,e){return f(n,e)},__wbindgen_init_externref_table:function(){let n=s.__wbindgen_externrefs,e=n.grow(4);n.set(0,void 0),n.set(e+0,void 0),n.set(e+1,null),n.set(e+2,!0),n.set(e+3,!1)}}}}var zn=typeof FinalizationRegistry>"u"?{register:()=>{},unregister:()=>{}}:new FinalizationRegistry(r=>s.__wbg_lint_free(r,1)),Rn=typeof FinalizationRegistry>"u"?{register:()=>{},unregister:()=>{}}:new FinalizationRegistry(r=>s.__wbg_linter_free(r,1)),Nn=typeof FinalizationRegistry>"u"?{register:()=>{},unregister:()=>{}}:new FinalizationRegistry(r=>s.__wbg_organizedgroup_free(r,1)),Cn=typeof FinalizationRegistry>"u"?{register:()=>{},unregister:()=>{}}:new FinalizationRegistry(r=>s.__wbg_span_free(r,1)),Dn=typeof FinalizationRegistry>"u"?{register:()=>{},unregister:()=>{}}:new FinalizationRegistry(r=>s.__wbg_suggestion_free(r,1));function Zn(r){let n=s.__externref_table_alloc();return s.__wbindgen_externrefs.set(n,r),n}function mn(r,n){if(!(r instanceof n))throw new Error(`expected instance of ${n.name}`)}function Ln(r){let n=typeof r;if(n=="number"||n=="boolean"||r==null)return`${r}`;if(n=="string")return`"${r}"`;if(n=="symbol"){let i=r.description;return i==null?"Symbol":`Symbol(${i})`}if(n=="function"){let i=r.name;return typeof i=="string"&&i.length>0?`Function(${i})`:"Function"}if(Array.isArray(r)){let i=r.length,_="[";i>0&&(_+=Ln(r[0]));for(let o=1;o<i;o++)_+=", "+Ln(r[o]);return _+="]",_}let e=/\[object ([^\]]+)\]/.exec(toString.call(r)),t;if(e&&e.length>1)t=e[1];else return toString.call(r);if(t=="Object")try{return"Object("+JSON.stringify(r)+")"}catch{return"Object"}return r instanceof Error?`${r.name}: ${r.message}
${r.stack}`:t}function Q(r,n){r=r>>>0;let e=h(),t=[];for(let i=r;i<r+4*n;i+=4)t.push(s.__wbindgen_externrefs.get(e.getUint32(i,!0)));return s.__externref_drop_slice(r,n),t}function yn(r,n){return r=r>>>0,V().subarray(r/1,r/1+n)}var J=null;function Te(){return(J===null||J.byteLength===0)&&(J=new BigUint64Array(s.memory.buffer)),J}var M=null;function h(){return(M===null||M.buffer.detached===!0||M.buffer.detached===void 0&&M.buffer!==s.memory.buffer)&&(M=new DataView(s.memory.buffer)),M}function f(r,n){return Me(r>>>0,n)}var q=null;function V(){return(q===null||q.byteLength===0)&&(q=new Uint8Array(s.memory.buffer)),q}function C(r,n){try{return r.apply(this,n)}catch(e){let t=Zn(e);s.__wbindgen_exn_store(t)}}function A(r){return r==null}function Ee(r,n){let e=n(r.length*8,8)>>>0;return Te().set(r,e/8),d=r.length,e}function Oe(r,n){let e=n(r.length*1,1)>>>0;return V().set(r,e/1),d=r.length,e}function Wn(r,n){let e=n(r.length*4,4)>>>0;for(let t=0;t<r.length;t++){let i=Zn(r[t]);h().setUint32(e+4*t,i,!0)}return d=r.length,e}function m(r,n,e){if(e===void 0){let l=Y.encode(r),c=n(l.length,1)>>>0;return V().subarray(c,c+l.length).set(l),d=l.length,c}let t=r.length,i=n(t,1)>>>0,_=V(),o=0;for(;o<t;o++){let l=r.charCodeAt(o);if(l>127)break;_[i+o]=l}if(o!==t){o!==0&&(r=r.slice(o)),i=e(i,t,t=o+r.length*3,1)>>>0;let l=V().subarray(i+o,i+t),c=Y.encodeInto(r,l);o+=c.written,i=e(i,t,o,1)>>>0}return d=o,i}function j(r){let n=s.__wbindgen_externrefs.get(r);return s.__externref_table_dealloc(r),n}var an=new TextDecoder("utf-8",{ignoreBOM:!0,fatal:!0});an.decode();var Fe=2146435072,hn=0;function Me(r,n){return hn+=n,hn>=Fe&&(an=new TextDecoder("utf-8",{ignoreBOM:!0,fatal:!0}),an.decode(),hn=n),an.decode(V().subarray(r,r+n))}var Y=new TextEncoder;"encodeInto"in Y||(Y.encodeInto=function(r,n){let e=Y.encode(r);return n.set(e),{read:r.length,written:e.length}});var d=0,s;function ne(r,n){return s=r.exports,J=null,M=null,q=null,s.__wbindgen_start(),s}async function ke(r,n){if(typeof Response=="function"&&r instanceof Response){if(typeof WebAssembly.instantiateStreaming=="function")try{return await WebAssembly.instantiateStreaming(r,n)}catch(i){if(r.ok&&e(r.type)&&r.headers.get("Content-Type")!=="application/wasm")console.warn("`WebAssembly.instantiateStreaming` failed because your server does not serve Wasm with `application/wasm` MIME type. Falling back to `WebAssembly.instantiate` which is slower. Original error:\n",i);else throw i}let t=await r.arrayBuffer();return await WebAssembly.instantiate(t,n)}else{let t=await WebAssembly.instantiate(r,n);return t instanceof WebAssembly.Instance?{instance:t,module:r}:t}function e(t){switch(t){case"basic":case"cors":case"default":return!0}return!1}}function ze(r){if(s!==void 0)return s;r!==void 0&&(Object.getPrototypeOf(r)===Object.prototype?{module:r}=r:console.warn("using deprecated parameters for `initSync()`; pass a single object instead"));let n=Xn();r instanceof WebAssembly.Module||(r=new WebAssembly.Module(r));let e=new WebAssembly.Instance(r,n);return ne(e)}async function ee(r){if(s!==void 0)return s;r!==void 0&&(Object.getPrototypeOf(r)===Object.prototype?{module_or_path:r}=r:console.warn("using deprecated parameters for the initialization function; pass a single object instead")),r===void 0&&(r=new URL);let n=Xn();(typeof r=="string"||typeof Request=="function"&&r instanceof Request||typeof URL=="function"&&r instanceof URL)&&(r=fetch(r));let{instance:e}=await ke(await r,n);return ne(e)}var Re=Object.freeze(Object.defineProperty({__proto__:null,Dialect:N,Language:W,Lint:z,Linter:jn,OrganizedGroup:ln,Span:cn,Suggestion:nn,SuggestionKind:Yn,default:ee,get_default_lint_config:xe,get_default_lint_config_as_json:Ae,initSync:ze,setup:Le,to_title_case:We},Symbol.toStringTag,{value:"Module"})),Ne=Object.freeze({American:0,0:"American",British:1,1:"British",Australian:2,2:"Australian",Canadian:3,3:"Canadian",Indian:4,4:"Indian"}),Ce=Object.freeze({Plain:0,0:"Plain",Markdown:1,1:"Markdown",Typst:2,2:"Typst"}),E=class r{static __wrap(n){let e=Object.create(r.prototype);return e.__wbg_ptr=n,Un.register(e,e.__wbg_ptr,e),e}static __unwrap(n){return n instanceof r?n.__destroy_into_raw():0}__destroy_into_raw(){let n=this.__wbg_ptr;return this.__wbg_ptr=0,Un.unregister(this),n}free(){let n=this.__destroy_into_raw();a.__wbg_lint_free(n,0)}static from_json(n){let e=y(n,a.__wbindgen_malloc,a.__wbindgen_realloc),t=p,i=a.lint_from_json(e,t);if(i[2])throw x(i[1]);return r.__wrap(i[0])}get_problem_text(){let n,e;try{let t=a.lint_get_problem_text(this.__wbg_ptr);return n=t[0],e=t[1],u(t[0],t[1])}finally{a.__wbindgen_free(n,e,1)}}lint_kind(){let n,e;try{let t=a.lint_lint_kind(this.__wbg_ptr);return n=t[0],e=t[1],u(t[0],t[1])}finally{a.__wbindgen_free(n,e,1)}}lint_kind_pretty(){let n,e;try{let t=a.lint_lint_kind_pretty(this.__wbg_ptr);return n=t[0],e=t[1],u(t[0],t[1])}finally{a.__wbindgen_free(n,e,1)}}message(){let n,e;try{let t=a.lint_message(this.__wbg_ptr);return n=t[0],e=t[1],u(t[0],t[1])}finally{a.__wbindgen_free(n,e,1)}}message_html(){let n,e;try{let t=a.lint_message_html(this.__wbg_ptr);return n=t[0],e=t[1],u(t[0],t[1])}finally{a.__wbindgen_free(n,e,1)}}span(){let n=a.lint_span(this.__wbg_ptr);return P.__wrap(n)}suggestion_count(){return a.lint_suggestion_count(this.__wbg_ptr)>>>0}suggestions(){let n=a.lint_suggestions(this.__wbg_ptr);var e=X(n[0],n[1]).slice();return a.__wbindgen_free(n[0],n[1]*4,4),e}to_json(){let n,e;try{let t=a.lint_to_json(this.__wbg_ptr);return n=t[0],e=t[1],u(t[0],t[1])}finally{a.__wbindgen_free(n,e,1)}}};Symbol.dispose&&(E.prototype[Symbol.dispose]=E.prototype.free);var en=class r{static __wrap(n){let e=Object.create(r.prototype);return e.__wbg_ptr=n,Vn.register(e,e.__wbg_ptr,e),e}__destroy_into_raw(){let n=this.__wbg_ptr;return this.__wbg_ptr=0,Vn.unregister(this),n}free(){let n=this.__destroy_into_raw();a.__wbg_linter_free(n,0)}apply_suggestion(n,e,t){let i,_;try{let c=y(n,a.__wbindgen_malloc,a.__wbindgen_realloc),b=p;vn(e,E),vn(t,R);let g=a.linter_apply_suggestion(this.__wbg_ptr,c,b,e.__wbg_ptr,t.__wbg_ptr);var o=g[0],l=g[1];if(g[3])throw o=0,l=0,x(g[2]);return i=o,_=l,u(o,l)}finally{a.__wbindgen_free(i,_,1)}}clear_ignored_lints(){a.linter_clear_ignored_lints(this.__wbg_ptr)}clear_words(){a.linter_clear_words(this.__wbg_ptr)}context_hash(n,e){let t=y(n,a.__wbindgen_malloc,a.__wbindgen_realloc),i=p;vn(e,E);let _=a.linter_context_hash(this.__wbg_ptr,t,i,e.__wbg_ptr);return BigInt.asUintN(64,_)}export_ignored_lints(){let n,e;try{let t=a.linter_export_ignored_lints(this.__wbg_ptr);return n=t[0],e=t[1],u(t[0],t[1])}finally{a.__wbindgen_free(n,e,1)}}export_words(){let n=a.linter_export_words(this.__wbg_ptr);var e=X(n[0],n[1]).slice();return a.__wbindgen_free(n[0],n[1]*4,4),e}generate_stats_file(){let n,e;try{let t=a.linter_generate_stats_file(this.__wbg_ptr);return n=t[0],e=t[1],u(t[0],t[1])}finally{a.__wbindgen_free(n,e,1)}}get_dialect(){return a.linter_get_dialect(this.__wbg_ptr)}get_lint_config_as_json(){let n,e;try{let t=a.linter_get_lint_config_as_json(this.__wbg_ptr);return n=t[0],e=t[1],u(t[0],t[1])}finally{a.__wbindgen_free(n,e,1)}}get_lint_config_as_object(){return a.linter_get_lint_config_as_object(this.__wbg_ptr)}get_lint_descriptions_as_json(){let n,e;try{let t=a.linter_get_lint_descriptions_as_json(this.__wbg_ptr);return n=t[0],e=t[1],u(t[0],t[1])}finally{a.__wbindgen_free(n,e,1)}}get_lint_descriptions_as_object(){return a.linter_get_lint_descriptions_as_object(this.__wbg_ptr)}get_lint_descriptions_html_as_json(){let n,e;try{let t=a.linter_get_lint_descriptions_html_as_json(this.__wbg_ptr);return n=t[0],e=t[1],u(t[0],t[1])}finally{a.__wbindgen_free(n,e,1)}}get_lint_descriptions_html_as_object(){return a.linter_get_lint_descriptions_html_as_object(this.__wbg_ptr)}get_structured_lint_config_as_json(){let n,e;try{let t=a.linter_get_structured_lint_config_as_json(this.__wbg_ptr);return n=t[0],e=t[1],u(t[0],t[1])}finally{a.__wbindgen_free(n,e,1)}}get_structured_lint_config_as_object(){return a.linter_get_structured_lint_config_as_object(this.__wbg_ptr)}ignore_hashes(n){let e=Ge(n,a.__wbindgen_malloc),t=p;a.linter_ignore_hashes(this.__wbg_ptr,e,t)}ignore_lints(n,e){let t=y(n,a.__wbindgen_malloc,a.__wbindgen_realloc),i=p,_=En(e,a.__wbindgen_malloc),o=p;a.linter_ignore_lints(this.__wbg_ptr,t,i,_,o)}import_ignored_lints(n){let e=y(n,a.__wbindgen_malloc,a.__wbindgen_realloc),t=p,i=a.linter_import_ignored_lints(this.__wbg_ptr,e,t);if(i[1])throw x(i[0])}import_stats_file(n){let e=y(n,a.__wbindgen_malloc,a.__wbindgen_realloc),t=p,i=a.linter_import_stats_file(this.__wbg_ptr,e,t);if(i[1])throw x(i[0])}import_weirpack(n){let e=Je(n,a.__wbindgen_malloc),t=p,i=a.linter_import_weirpack(this.__wbg_ptr,e,t);if(i[2])throw x(i[1]);return x(i[0])}import_words(n){let e=En(n,a.__wbindgen_malloc),t=p;a.linter_import_words(this.__wbg_ptr,e,t)}is_likely_english(n){let e=y(n,a.__wbindgen_malloc,a.__wbindgen_realloc),t=p;return a.linter_is_likely_english(this.__wbg_ptr,e,t)!==0}isolate_english(n){let e,t;try{let i=y(n,a.__wbindgen_malloc,a.__wbindgen_realloc),_=p,o=a.linter_isolate_english(this.__wbg_ptr,i,_);return e=o[0],t=o[1],u(o[0],o[1])}finally{a.__wbindgen_free(e,t,1)}}lint(n,e,t,i,_){let o=y(n,a.__wbindgen_malloc,a.__wbindgen_realloc),l=p;var c=L(i)?0:y(i,a.__wbindgen_malloc,a.__wbindgen_realloc),b=p;let g=a.linter_lint(this.__wbg_ptr,o,l,e,t,c,b,_);var F=X(g[0],g[1]).slice();return a.__wbindgen_free(g[0],g[1]*4,4),F}static new(n){let e=a.linter_new(n);return r.__wrap(e)}organized_lints(n,e,t,i,_){let o=y(n,a.__wbindgen_malloc,a.__wbindgen_realloc),l=p;var c=L(i)?0:y(i,a.__wbindgen_malloc,a.__wbindgen_realloc),b=p;let g=a.linter_organized_lints(this.__wbg_ptr,o,l,e,t,c,b,_);var F=X(g[0],g[1]).slice();return a.__wbindgen_free(g[0],g[1]*4,4),F}set_lint_config_from_json(n){let e=y(n,a.__wbindgen_malloc,a.__wbindgen_realloc),t=p,i=a.linter_set_lint_config_from_json(this.__wbg_ptr,e,t);if(i[1])throw x(i[0])}set_lint_config_from_object(n){let e=a.linter_set_lint_config_from_object(this.__wbg_ptr,n);if(e[1])throw x(e[0])}summarize_stats(n,e){return a.linter_summarize_stats(this.__wbg_ptr,!L(n),L(n)?BigInt(0):n,!L(e),L(e)?BigInt(0):e)}};Symbol.dispose&&(en.prototype[Symbol.dispose]=en.prototype.free);var B=class r{static __wrap(n){let e=Object.create(r.prototype);return e.__wbg_ptr=n,In.register(e,e.__wbg_ptr,e),e}__destroy_into_raw(){let n=this.__wbg_ptr;return this.__wbg_ptr=0,In.unregister(this),n}free(){let n=this.__destroy_into_raw();a.__wbg_organizedgroup_free(n,0)}get group(){let n,e;try{let t=a.__wbg_get_organizedgroup_group(this.__wbg_ptr);return n=t[0],e=t[1],u(t[0],t[1])}finally{a.__wbindgen_free(n,e,1)}}get lints(){let n=a.__wbg_get_organizedgroup_lints(this.__wbg_ptr);var e=X(n[0],n[1]).slice();return a.__wbindgen_free(n[0],n[1]*4,4),e}set group(n){let e=y(n,a.__wbindgen_malloc,a.__wbindgen_realloc),t=p;a.__wbg_set_organizedgroup_group(this.__wbg_ptr,e,t)}set lints(n){let e=En(n,a.__wbindgen_malloc),t=p;a.__wbg_set_organizedgroup_lints(this.__wbg_ptr,e,t)}};Symbol.dispose&&(B.prototype[Symbol.dispose]=B.prototype.free);var P=class r{static __wrap(n){let e=Object.create(r.prototype);return e.__wbg_ptr=n,Bn.register(e,e.__wbg_ptr,e),e}__destroy_into_raw(){let n=this.__wbg_ptr;return this.__wbg_ptr=0,Bn.unregister(this),n}free(){let n=this.__destroy_into_raw();a.__wbg_span_free(n,0)}get end(){return a.__wbg_get_span_end(this.__wbg_ptr)>>>0}get start(){return a.__wbg_get_span_start(this.__wbg_ptr)>>>0}set end(n){a.__wbg_set_span_end(this.__wbg_ptr,n)}set start(n){a.__wbg_set_span_start(this.__wbg_ptr,n)}static from_json(n){let e=y(n,a.__wbindgen_malloc,a.__wbindgen_realloc),t=p,i=a.span_from_json(e,t);if(i[2])throw x(i[1]);return r.__wrap(i[0])}is_empty(){return a.span_is_empty(this.__wbg_ptr)!==0}len(){return a.span_len(this.__wbg_ptr)>>>0}static new(n,e){let t=a.span_new(n,e);return r.__wrap(t)}to_json(){let n,e;try{let t=a.span_to_json(this.__wbg_ptr);return n=t[0],e=t[1],u(t[0],t[1])}finally{a.__wbindgen_free(n,e,1)}}};Symbol.dispose&&(P.prototype[Symbol.dispose]=P.prototype.free);var R=class r{static __wrap(n){let e=Object.create(r.prototype);return e.__wbg_ptr=n,Pn.register(e,e.__wbg_ptr,e),e}__destroy_into_raw(){let n=this.__wbg_ptr;return this.__wbg_ptr=0,Pn.unregister(this),n}free(){let n=this.__destroy_into_raw();a.__wbg_suggestion_free(n,0)}static from_json(n){let e=y(n,a.__wbindgen_malloc,a.__wbindgen_realloc),t=p,i=a.suggestion_from_json(e,t);if(i[2])throw x(i[1]);return r.__wrap(i[0])}get_replacement_text(){let n,e;try{let t=a.suggestion_get_replacement_text(this.__wbg_ptr);return n=t[0],e=t[1],u(t[0],t[1])}finally{a.__wbindgen_free(n,e,1)}}kind(){return a.suggestion_kind(this.__wbg_ptr)}to_json(){let n,e;try{let t=a.suggestion_to_json(this.__wbg_ptr);return n=t[0],e=t[1],u(t[0],t[1])}finally{a.__wbindgen_free(n,e,1)}}};Symbol.dispose&&(R.prototype[Symbol.dispose]=R.prototype.free);var De=Object.freeze({Replace:0,0:"Replace",Remove:1,1:"Remove",InsertAfter:2,2:"InsertAfter"});function Ue(){return a.get_default_lint_config()}function Ve(){let r,n;try{let e=a.get_default_lint_config_as_json();return r=e[0],n=e[1],u(e[0],e[1])}finally{a.__wbindgen_free(r,n,1)}}function Ie(){a.setup()}function Be(r){let n,e;try{let t=y(r,a.__wbindgen_malloc,a.__wbindgen_realloc),i=p,_=a.to_title_case(t,i);return n=_[0],e=_[1],u(_[0],_[1])}finally{a.__wbindgen_free(n,e,1)}}function te(){return{__proto__:null,"./harper_wasm_bg.js":{__proto__:null,__wbg_Error_bce6d499ff0a4aff:function(n,e){return Error(u(n,e))},__wbg_String_8564e559799eccda:function(n,e){let t=String(e),i=y(t,a.__wbindgen_malloc,a.__wbindgen_realloc),_=p;v().setInt32(n+4,_,!0),v().setInt32(n+0,i,!0)},__wbg___wbindgen_boolean_get_2304fb8c853028c8:function(n){let e=n,t=typeof e=="boolean"?e:void 0;return L(t)?16777215:t?1:0},__wbg___wbindgen_debug_string_edece8177ad01481:function(n,e){let t=Tn(e),i=y(t,a.__wbindgen_malloc,a.__wbindgen_realloc),_=p;v().setInt32(n+4,_,!0),v().setInt32(n+0,i,!0)},__wbg___wbindgen_is_function_5cd60d5cf78b4eef:function(n){return typeof n=="function"},__wbg___wbindgen_is_object_b4593df85baada48:function(n){let e=n;return typeof e=="object"&&e!==null},__wbg___wbindgen_is_string_dde0fd9020db4434:function(n){return typeof n=="string"},__wbg___wbindgen_jsval_loose_eq_0ad77b7717db155c:function(n,e){return n==e},__wbg___wbindgen_number_get_f73a1244370fcc2c:function(n,e){let t=e,i=typeof t=="number"?t:void 0;v().setFloat64(n+8,L(i)?0:i,!0),v().setInt32(n+0,!L(i),!0)},__wbg___wbindgen_string_get_d109740c0d18f4d7:function(n,e){let t=e,i=typeof t=="string"?t:void 0;var _=L(i)?0:y(i,a.__wbindgen_malloc,a.__wbindgen_realloc),o=p;v().setInt32(n+4,o,!0),v().setInt32(n+0,_,!0)},__wbg___wbindgen_throw_9c31b086c2b26051:function(n,e){throw new Error(u(n,e))},__wbg_call_13665d9f14390edc:function(){return D(function(n,e){return n.call(e)},arguments)},__wbg_done_54b8da57023b7ed2:function(n){return n.done},__wbg_entries_564a7e8b1e54ede5:function(n){return Object.entries(n)},__wbg_error_a6fa202b58aa1cd3:function(n,e){let t,i;try{t=n,i=e,console.error(u(n,e))}finally{a.__wbindgen_free(t,i,1)}},__wbg_getRandomValues_3f44b700395062e5:function(){return D(function(n,e){globalThis.crypto.getRandomValues(Sn(n,e))},arguments)},__wbg_getRandomValues_d49329ff89a07af1:function(){return D(function(n,e){globalThis.crypto.getRandomValues(Sn(n,e))},arguments)},__wbg_getTime_09f1dd40a44edb30:function(n){return n.getTime()},__wbg_get_3e9a707ab7d352eb:function(){return D(function(n,e){return Reflect.get(n,e)},arguments)},__wbg_get_98fdf51d029a75eb:function(n,e){return n[e>>>0]},__wbg_get_unchecked_1dfe6d05ad91d9b7:function(n,e){return n[e>>>0]},__wbg_instanceof_ArrayBuffer_53db37b06f6b9afe:function(n){let e;try{e=n instanceof ArrayBuffer}catch{e=!1}return e},__wbg_instanceof_Uint8Array_abd07d4bd221d50b:function(n){let e;try{e=n instanceof Uint8Array}catch{e=!1}return e},__wbg_iterator_1441b47f341dc34f:function(){return Symbol.iterator},__wbg_length_2591a0f4f659a55c:function(n){return n.length},__wbg_length_56fcd3e2b7e0299d:function(n){return n.length},__wbg_lint_new:function(n){return E.__wrap(n)},__wbg_lint_unwrap:function(n){return E.__unwrap(n)},__wbg_log_0c201ade58bb55e1:function(n,e,t,i,_,o,l,c){let b,g;try{b=n,g=e,console.log(u(n,e),u(t,i),u(_,o),u(l,c))}finally{a.__wbindgen_free(b,g,1)}},__wbg_log_ce2c4456b290c5e7:function(n,e){let t,i;try{t=n,i=e,console.log(u(n,e))}finally{a.__wbindgen_free(t,i,1)}},__wbg_mark_b4d943f3bc2d2404:function(n,e){performance.mark(u(n,e))},__wbg_measure_84362959e621a2c1:function(){return D(function(n,e,t,i){let _,o,l,c;try{_=n,o=e,l=t,c=i,performance.measure(u(n,e),u(t,i))}finally{a.__wbindgen_free(_,o,1),a.__wbindgen_free(l,c,1)}},arguments)},__wbg_new_02d162bc6cf02f60:function(){return new Object},__wbg_new_070df68d66325372:function(){return new Map},__wbg_new_0_2722fcdb71a888a6:function(){return new Date},__wbg_new_227d7c05414eb861:function(){return new Error},__wbg_new_310879b66b6e95e1:function(){return new Array},__wbg_new_7ddec6de44ff8f5d:function(n){return new Uint8Array(n)},__wbg_next_2a4e19f4f5083b0f:function(n){return n.next},__wbg_next_6429a146bf756f93:function(){return D(function(n){return n.next()},arguments)},__wbg_organizedgroup_new:function(n){return B.__wrap(n)},__wbg_prototypesetcall_5f9bdc8d75e07276:function(n,e,t){Uint8Array.prototype.set.call(Sn(n,e),t)},__wbg_set_6be42768c690e380:function(n,e,t){n[e]=t},__wbg_set_78ea6a19f4818587:function(n,e,t){n[e>>>0]=t},__wbg_set_facb7a5914e0fa39:function(n,e,t){return n.set(e,t)},__wbg_stack_3b0d974bbf31e44f:function(n,e){let t=e.stack,i=y(t,a.__wbindgen_malloc,a.__wbindgen_realloc),_=p;v().setInt32(n+4,_,!0),v().setInt32(n+0,i,!0)},__wbg_suggestion_new:function(n){return R.__wrap(n)},__wbg_value_9cc0518af87a489c:function(n){return n.value},__wbindgen_cast_0000000000000001:function(n){return n},__wbindgen_cast_0000000000000002:function(n,e){return u(n,e)},__wbindgen_init_externref_table:function(){let n=a.__wbindgen_externrefs,e=n.grow(4);n.set(0,void 0),n.set(e+0,void 0),n.set(e+1,null),n.set(e+2,!0),n.set(e+3,!1)}}}}var Un=typeof FinalizationRegistry>"u"?{register:()=>{},unregister:()=>{}}:new FinalizationRegistry(r=>a.__wbg_lint_free(r,1)),Vn=typeof FinalizationRegistry>"u"?{register:()=>{},unregister:()=>{}}:new FinalizationRegistry(r=>a.__wbg_linter_free(r,1)),In=typeof FinalizationRegistry>"u"?{register:()=>{},unregister:()=>{}}:new FinalizationRegistry(r=>a.__wbg_organizedgroup_free(r,1)),Bn=typeof FinalizationRegistry>"u"?{register:()=>{},unregister:()=>{}}:new FinalizationRegistry(r=>a.__wbg_span_free(r,1)),Pn=typeof FinalizationRegistry>"u"?{register:()=>{},unregister:()=>{}}:new FinalizationRegistry(r=>a.__wbg_suggestion_free(r,1));function re(r){let n=a.__externref_table_alloc();return a.__wbindgen_externrefs.set(n,r),n}function vn(r,n){if(!(r instanceof n))throw new Error(`expected instance of ${n.name}`)}function Tn(r){let n=typeof r;if(n=="number"||n=="boolean"||r==null)return`${r}`;if(n=="string")return`"${r}"`;if(n=="symbol"){let i=r.description;return i==null?"Symbol":`Symbol(${i})`}if(n=="function"){let i=r.name;return typeof i=="string"&&i.length>0?`Function(${i})`:"Function"}if(Array.isArray(r)){let i=r.length,_="[";i>0&&(_+=Tn(r[0]));for(let o=1;o<i;o++)_+=", "+Tn(r[o]);return _+="]",_}let e=/\[object ([^\]]+)\]/.exec(toString.call(r)),t;if(e&&e.length>1)t=e[1];else return toString.call(r);if(t=="Object")try{return"Object("+JSON.stringify(r)+")"}catch{return"Object"}return r instanceof Error?`${r.name}: ${r.message}
${r.stack}`:t}function X(r,n){r=r>>>0;let e=v(),t=[];for(let i=r;i<r+4*n;i+=4)t.push(a.__wbindgen_externrefs.get(e.getUint32(i,!0)));return a.__externref_drop_slice(r,n),t}function Sn(r,n){return r=r>>>0,I().subarray(r/1,r/1+n)}var H=null;function Pe(){return(H===null||H.byteLength===0)&&(H=new BigUint64Array(a.memory.buffer)),H}var k=null;function v(){return(k===null||k.buffer.detached===!0||k.buffer.detached===void 0&&k.buffer!==a.memory.buffer)&&(k=new DataView(a.memory.buffer)),k}function u(r,n){return He(r>>>0,n)}var K=null;function I(){return(K===null||K.byteLength===0)&&(K=new Uint8Array(a.memory.buffer)),K}function D(r,n){try{return r.apply(this,n)}catch(e){let t=re(e);a.__wbindgen_exn_store(t)}}function L(r){return r==null}function Ge(r,n){let e=n(r.length*8,8)>>>0;return Pe().set(r,e/8),p=r.length,e}function Je(r,n){let e=n(r.length*1,1)>>>0;return I().set(r,e/1),p=r.length,e}function En(r,n){let e=n(r.length*4,4)>>>0;for(let t=0;t<r.length;t++){let i=re(r[t]);v().setUint32(e+4*t,i,!0)}return p=r.length,e}function y(r,n,e){if(e===void 0){let l=Z.encode(r),c=n(l.length,1)>>>0;return I().subarray(c,c+l.length).set(l),p=l.length,c}let t=r.length,i=n(t,1)>>>0,_=I(),o=0;for(;o<t;o++){let l=r.charCodeAt(o);if(l>127)break;_[i+o]=l}if(o!==t){o!==0&&(r=r.slice(o)),i=e(i,t,t=o+r.length*3,1)>>>0;let l=I().subarray(i+o,i+t),c=Z.encodeInto(r,l);o+=c.written,i=e(i,t,o,1)>>>0}return p=o,i}function x(r){let n=a.__wbindgen_externrefs.get(r);return a.__externref_table_dealloc(r),n}var _n=new TextDecoder("utf-8",{ignoreBOM:!0,fatal:!0});_n.decode();var qe=2146435072,$n=0;function He(r,n){return $n+=n,$n>=qe&&(_n=new TextDecoder("utf-8",{ignoreBOM:!0,fatal:!0}),_n.decode(),$n=n),_n.decode(I().subarray(r,r+n))}var Z=new TextEncoder;"encodeInto"in Z||(Z.encodeInto=function(r,n){let e=Z.encode(r);return n.set(e),{read:r.length,written:e.length}});var p=0,a;function ie(r,n){return a=r.exports,H=null,k=null,K=null,a.__wbindgen_start(),a}async function Ke(r,n){if(typeof Response=="function"&&r instanceof Response){if(typeof WebAssembly.instantiateStreaming=="function")try{return await WebAssembly.instantiateStreaming(r,n)}catch(i){if(r.ok&&e(r.type)&&r.headers.get("Content-Type")!=="application/wasm")console.warn("`WebAssembly.instantiateStreaming` failed because your server does not serve Wasm with `application/wasm` MIME type. Falling back to `WebAssembly.instantiate` which is slower. Original error:\n",i);else throw i}let t=await r.arrayBuffer();return await WebAssembly.instantiate(t,n)}else{let t=await WebAssembly.instantiate(r,n);return t instanceof WebAssembly.Instance?{instance:t,module:r}:t}function e(t){switch(t){case"basic":case"cors":case"default":return!0}return!1}}function Qe(r){if(a!==void 0)return a;r!==void 0&&(Object.getPrototypeOf(r)===Object.prototype?{module:r}=r:console.warn("using deprecated parameters for `initSync()`; pass a single object instead"));let n=te();r instanceof WebAssembly.Module||(r=new WebAssembly.Module(r));let e=new WebAssembly.Instance(r,n);return ie(e)}async function Ye(r){if(a!==void 0)return a;r!==void 0&&(Object.getPrototypeOf(r)===Object.prototype?{module_or_path:r}=r:console.warn("using deprecated parameters for the initialization function; pass a single object instead")),r===void 0&&(r=new URL);let n=te();(typeof r=="string"||typeof Request=="function"&&r instanceof Request||typeof URL=="function"&&r instanceof URL)&&(r=fetch(r));let{instance:e}=await Ke(await r,n);return ie(e)}var Xe=Object.freeze(Object.defineProperty({__proto__:null,Dialect:Ne,Language:Ce,Lint:E,Linter:en,OrganizedGroup:B,Span:P,Suggestion:R,SuggestionKind:De,default:Ye,get_default_lint_config:Ue,get_default_lint_config_as_json:Ve,initSync:Qe,setup:Ie,to_title_case:Be},Symbol.toStringTag,{value:"Module"})),Ze=class on extends Promise{constructor(n){super(e=>{e()}),kn(this,U),kn(this,S),tn(this,U,n)}static from(n){return new on(e=>{e(n())})}static resolve(n){return new on(e=>{e(n)})}static reject(n){return new on((e,t)=>{t(n)})}then(n,e){return T(this,S)??tn(this,S,new Promise(T(this,U))),T(this,S).then(n,e)}catch(n){return T(this,S)??tn(this,S,new Promise(T(this,U))),T(this,S).catch(n)}finally(n){return T(this,S)??tn(this,S,new Promise(T(this,U))),T(this,S).finally(n)}};U=new WeakMap;S=new WeakMap;var fn=Ze,nt=(r,n,e,t)=>{if(e==="length"||e==="prototype"||e==="arguments"||e==="caller")return;let i=Object.getOwnPropertyDescriptor(r,e),_=Object.getOwnPropertyDescriptor(n,e);!et(i,_)&&t||Object.defineProperty(r,e,_)},et=function(r,n){return r===void 0||r.configurable||r.writable===n.writable&&r.enumerable===n.enumerable&&r.configurable===n.configurable&&(r.writable||r.value===n.value)},tt=(r,n)=>{let e=Object.getPrototypeOf(n);e!==Object.getPrototypeOf(r)&&Object.setPrototypeOf(r,e)},rt=(r,n)=>`/* Wrapped ${r}*/
${n}`,it=Object.getOwnPropertyDescriptor(Function.prototype,"toString"),st=Object.getOwnPropertyDescriptor(Function.prototype.toString,"name"),at=(r,n,e)=>{let t=e===""?"":`with ${e.trim()}() `,i=rt.bind(null,t,n.toString());Object.defineProperty(i,"name",st),Object.defineProperty(r,"toString",{...it,value:i})};function _t(r,n,{ignoreNonConfigurable:e=!1}={}){let{name:t}=r;for(let i of Reflect.ownKeys(n))nt(r,n,i,e);return tt(r,n),at(r,n,t),r}var ot=new WeakMap;function Gn(r,{cacheKey:n=([t])=>t,cache:e=new Map}={}){let t=new Map,i=function(..._){let o=n(_);if(t.has(o))return t.get(o);let l=(async()=>{try{if(e&&await e.has(o))return await e.get(o);let b=await r.apply(this,_);try{return b}finally{e&&await e.set(o,b)}}finally{t.delete(o)}})();return t.set(o,l),l};return _t(i,r,{ignoreNonConfigurable:!0}),ot.set(i,e),i}function se(r){return r.includes("harper_wasm_slim")?"slim":"full"}function ae(r){return r.glueFlavor??se(typeof r.url=="string"?r.url:r.url.href)}function lt(r){return r==="slim"?Re:Xe}function ct(r,n){return n==="slim"?r:r.includes("harper_wasm_bg.wasm")?r.replace("harper_wasm_bg.wasm","harper_wasm_slim_bg.wasm"):null}function Jn(r){return typeof process<"u"&&r.startsWith("file://")?import("fs").then(n=>new Promise((e,t)=>{n.readFile(new URL(r).pathname,(i,_)=>{i&&t(i),e(_)})})):r}async function qn(r,n){let e=lt(n),t=ct(r,n);if(t!=null)try{await ee({module_or_path:Jn(t)})}catch(i){if(n==="slim")throw i}return await e.default({module_or_path:Jn(r)}),e}var gt={full:Gn(r=>qn(r,"full")),slim:Gn(r=>qn(r,"slim"))};function _e(r,n){return gt[n](r)}function un(r,n){return gn.create(r,n)}var gn=class{constructor(){bn(this,"url",""),bn(this,"glueFlavor","full"),bn(this,"inner",null)}static create(n,e){let t=new On;return t.url=n,t.glueFlavor=e??se(typeof n=="string"?n:n.href),t.inner=fn.from(()=>_e(typeof t.url=="string"?t.url:t.url.href,t.glueFlavor)),t}async getDefaultLintConfigAsJSON(){return(await this.inner).get_default_lint_config_as_json()}async getDefaultLintConfig(){return(await this.inner).get_default_lint_config()}async toTitleCase(n){return(await this.inner).to_title_case(n)}async setup(){(await this.inner).setup()}},On=class extends gn{async createLinter(n){return(await this.getBinaryModule()).Linter.new(n??N.American)}async getBinaryModule(){return await fn.from(()=>_e(typeof this.url=="string"?this.url:this.url.href,this.glueFlavor))}};var ft=Object.defineProperty,ut=(r,n,e)=>n in r?ft(r,n,{enumerable:!0,configurable:!0,writable:!0,value:e}):r[n]=e,$=(r,n,e)=>ut(r,typeof n!="symbol"?n+"":n,e),dn=class{constructor(n){$(this,"binary"),$(this,"inner"),$(this,"disposed",!1),this.binary=n.binary,this.binary.setup(),this.inner=this.createInner(n.dialect)}createInner(n){return fn.from(async()=>(await this.binary.setup(),this.binary.createLinter(n)))}async setup(){await this.lint("",{language:"plaintext"});let n=await this.exportIgnoredLints();await this.importIgnoredLints(n)}async lint(n,e){let t=await this.inner,i=W.Markdown;switch(e?.language){case"plaintext":i=W.Plain;break;case"markdown":i=W.Markdown;break;case"typst":i=W.Typst}return t.lint(n,i,e?.forceAllHeadings??!1,e?.regex_mask,e?.dedup??!0)}async organizedLints(n,e){let t=await this.inner,i=W.Markdown;switch(e?.language){case"plaintext":i=W.Plain;break;case"markdown":i=W.Markdown;break;case"typst":i=W.Typst;break}let _=t.organized_lints(n,i,e?.forceAllHeadings??!1,e?.regex_mask,e?.dedup??!0),o={};for(let l of _)o[l.group]=l.lints,l.free();return o}async applySuggestion(n,e,t){return(await this.inner).apply_suggestion(n,e,t)}async isLikelyEnglish(n){return(await this.inner).is_likely_english(n)}async isolateEnglish(n){return(await this.inner).isolate_english(n)}async getLintConfig(){return(await this.inner).get_lint_config_as_object()}async getDefaultLintConfigAsJSON(){return await this.binary.getDefaultLintConfigAsJSON()}async getDefaultLintConfig(){return await this.binary.getDefaultLintConfig()}async getStructuredLintConfig(){return(await this.inner).get_structured_lint_config_as_object()}async getStructuredLintConfigJSON(){return(await this.inner).get_structured_lint_config_as_json()}async setLintConfig(n){(await this.inner).set_lint_config_from_object(n)}async getLintConfigAsJSON(){return(await this.inner).get_lint_config_as_json()}async setLintConfigWithJSON(n){(await this.inner).set_lint_config_from_json(n)}async toTitleCase(n){return await this.binary.toTitleCase(n)}async getLintDescriptions(){return(await this.inner).get_lint_descriptions_as_object()}async getLintDescriptionsAsJSON(){return(await this.inner).get_lint_descriptions_as_json()}async getLintDescriptionsHTML(){return(await this.inner).get_lint_descriptions_html_as_object()}async getLintDescriptionsHTMLAsJSON(){return(await this.inner).get_lint_descriptions_html_as_json()}async ignoreLint(n,e){return await this.ignoreLints(n,[e])}async ignoreLints(n,e){(await this.inner).ignore_lints(n,e)}async ignoreLintHash(n){(await this.inner).ignore_hashes(new BigUint64Array([n]))}async exportIgnoredLints(){return(await this.inner).export_ignored_lints()}async importIgnoredLints(n){(await this.inner).import_ignored_lints(n)}async contextHash(n,e){return(await this.inner).context_hash(n,e)}async clearIgnoredLints(){(await this.inner).clear_ignored_lints()}async clearWords(){return(await this.inner).clear_words()}async importWords(n){return(await this.inner).import_words(n)}async exportWords(){return(await this.inner).export_words()}async getDialect(){return(await this.inner).get_dialect()}async setDialect(n){let e=await this.inner;return e.get_dialect()!==n&&(e.free(),this.inner=this.createInner(n)),Promise.resolve()}async summarizeStats(n,e){return(await this.inner).summarize_stats(n,e)}async generateStatsFile(){return(await this.inner).generate_stats_file()}async importStatsFile(n){return(await this.inner).import_stats_file(n)}async loadWeirpackFromBlob(n){let e=new Uint8Array(await n.arrayBuffer());return this.loadWeirpackFromBytes(e)}async loadWeirpackFromBytes(n){let e=await this.inner,t=n instanceof Uint8Array?n:Uint8Array.from(n);return e.import_weirpack(t)}async dispose(){if(this.disposed)return;this.disposed=!0,(await this.inner).free()}};function dt(r,n){if(!r)throw new Error("Assertion failed")}var Fn=class{constructor(n){$(this,"binary"),this.binary=n,this.binary.setup()}async serializeArg(n){var e;let{Lint:t,Span:i,Suggestion:_}=await this.binary.getBinaryModule();if(Array.isArray(n))return{json:JSON.stringify(await Promise.all(n.map(l=>this.serializeArg(l)))),type:"Array"};let o=typeof n;switch(o){case"string":case"number":case"boolean":case"undefined":return{json:JSON.stringify(n),type:o};case"bigint":return{json:n.toString(),type:o}}if(n.to_json!==void 0){let l=n.to_json(),c,b=(e=n.constructor)==null?void 0:e.name;if(n instanceof t||b==="Lint"?c="Lint":n instanceof _||b==="Suggestion"?c="Suggestion":(n instanceof i||b==="Span")&&(c="Span"),c===void 0)throw new Error("Unhandled case: type undefined");return{json:l,type:c}}if(o=="object")return{json:JSON.stringify(await Promise.all(Object.entries(n).map(([l,c])=>this.serializeArg([l,c])))),type:"object"};throw new Error(`Unhandled case: ${n}`)}async serialize(n){return{procName:n.procName,args:await Promise.all(n.args.map(e=>this.serializeArg(e)))}}async deserializeArg(n){let{Lint:e,Span:t,Suggestion:i}=await this.binary.getBinaryModule();switch(n.type){case"bigint":return BigInt(n.json);case"undefined":return;case"boolean":case"number":case"string":return JSON.parse(n.json);case"Suggestion":return i.from_json(n.json);case"Lint":return e.from_json(n.json);case"Span":return t.from_json(n.json);case"Array":{let _=JSON.parse(n.json);return dt(Array.isArray(_)),await Promise.all(_.map(o=>this.deserializeArg(o)))}case"object":{let _=JSON.parse(n.json);return Object.fromEntries(await Promise.all(_.map(o=>this.deserializeArg(o))))}default:throw new Error(`Unhandled case: ${n.type}`)}}async deserialize(n){return{procName:n.procName,args:await Promise.all(n.args.map(e=>this.deserializeArg(e)))}}},le=`var __defProp = Object.defineProperty;
var __typeError = (msg) => {
  throw TypeError(msg);
};
var __defNormalProp = (obj, key, value) => key in obj ? __defProp(obj, key, { enumerable: true, configurable: true, writable: true, value }) : obj[key] = value;
var __publicField = (obj, key, value) => __defNormalProp(obj, typeof key !== "symbol" ? key + "" : key, value);
var __accessCheck = (obj, member, msg) => member.has(obj) || __typeError("Cannot " + msg);
var __privateGet = (obj, member, getter) => (__accessCheck(obj, member, "read from private field"), getter ? getter.call(obj) : member.get(obj));
var __privateAdd = (obj, member, value) => member.has(obj) ? __typeError("Cannot add the same private member more than once") : member instanceof WeakSet ? member.add(obj) : member.set(obj, value);
var __privateSet = (obj, member, value, setter) => (__accessCheck(obj, member, "write to private field"), setter ? setter.call(obj, value) : member.set(obj, value), value);
var _executor, _promise;
const Dialect$1 = Object.freeze({
  American: 0,
  "0": "American",
  British: 1,
  "1": "British",
  Australian: 2,
  "2": "Australian",
  Canadian: 3,
  "3": "Canadian",
  Indian: 4,
  "4": "Indian"
});
const Language$1 = Object.freeze({
  Plain: 0,
  "0": "Plain",
  Markdown: 1,
  "1": "Markdown",
  Typst: 2,
  "2": "Typst"
});
let Lint$1 = class Lint {
  static __wrap(ptr) {
    const obj = Object.create(Lint.prototype);
    obj.__wbg_ptr = ptr;
    LintFinalization$1.register(obj, obj.__wbg_ptr, obj);
    return obj;
  }
  static __unwrap(jsValue) {
    if (!(jsValue instanceof Lint)) {
      return 0;
    }
    return jsValue.__destroy_into_raw();
  }
  __destroy_into_raw() {
    const ptr = this.__wbg_ptr;
    this.__wbg_ptr = 0;
    LintFinalization$1.unregister(this);
    return ptr;
  }
  free() {
    const ptr = this.__destroy_into_raw();
    wasm$1.__wbg_lint_free(ptr, 0);
  }
  /**
   * @param {string} json
   * @returns {Lint}
   */
  static from_json(json) {
    const ptr0 = passStringToWasm0$1(json, wasm$1.__wbindgen_malloc, wasm$1.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN$1;
    const ret = wasm$1.lint_from_json(ptr0, len0);
    if (ret[2]) {
      throw takeFromExternrefTable0$1(ret[1]);
    }
    return Lint.__wrap(ret[0]);
  }
  /**
   * Get the content of the source material pointed to by [\`Self::span\`]
   * @returns {string}
   */
  get_problem_text() {
    let deferred1_0;
    let deferred1_1;
    try {
      const ret = wasm$1.lint_get_problem_text(this.__wbg_ptr);
      deferred1_0 = ret[0];
      deferred1_1 = ret[1];
      return getStringFromWasm0$1(ret[0], ret[1]);
    } finally {
      wasm$1.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
  }
  /**
   * Get a string representing the general category of the lint.
   * @returns {string}
   */
  lint_kind() {
    let deferred1_0;
    let deferred1_1;
    try {
      const ret = wasm$1.lint_lint_kind(this.__wbg_ptr);
      deferred1_0 = ret[0];
      deferred1_1 = ret[1];
      return getStringFromWasm0$1(ret[0], ret[1]);
    } finally {
      wasm$1.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
  }
  /**
   * Get a string representing the general category of the lint.
   * @returns {string}
   */
  lint_kind_pretty() {
    let deferred1_0;
    let deferred1_1;
    try {
      const ret = wasm$1.lint_lint_kind_pretty(this.__wbg_ptr);
      deferred1_0 = ret[0];
      deferred1_1 = ret[1];
      return getStringFromWasm0$1(ret[0], ret[1]);
    } finally {
      wasm$1.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
  }
  /**
   * Get a description of the error.
   * @returns {string}
   */
  message() {
    let deferred1_0;
    let deferred1_1;
    try {
      const ret = wasm$1.lint_message(this.__wbg_ptr);
      deferred1_0 = ret[0];
      deferred1_1 = ret[1];
      return getStringFromWasm0$1(ret[0], ret[1]);
    } finally {
      wasm$1.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
  }
  /**
   * Get a description of the error as HTML.
   * @returns {string}
   */
  message_html() {
    let deferred1_0;
    let deferred1_1;
    try {
      const ret = wasm$1.lint_message_html(this.__wbg_ptr);
      deferred1_0 = ret[0];
      deferred1_1 = ret[1];
      return getStringFromWasm0$1(ret[0], ret[1]);
    } finally {
      wasm$1.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
  }
  /**
   * Get the location of the problematic text.
   * @returns {Span}
   */
  span() {
    const ret = wasm$1.lint_span(this.__wbg_ptr);
    return Span$1.__wrap(ret);
  }
  /**
   * Equivalent to calling \`.length\` on the result of \`suggestions()\`.
   * @returns {number}
   */
  suggestion_count() {
    const ret = wasm$1.lint_suggestion_count(this.__wbg_ptr);
    return ret >>> 0;
  }
  /**
   * Get an array of any suggestions that may resolve the issue.
   * @returns {Suggestion[]}
   */
  suggestions() {
    const ret = wasm$1.lint_suggestions(this.__wbg_ptr);
    var v1 = getArrayJsValueFromWasm0$1(ret[0], ret[1]).slice();
    wasm$1.__wbindgen_free(ret[0], ret[1] * 4, 4);
    return v1;
  }
  /**
   * @returns {string}
   */
  to_json() {
    let deferred1_0;
    let deferred1_1;
    try {
      const ret = wasm$1.lint_to_json(this.__wbg_ptr);
      deferred1_0 = ret[0];
      deferred1_1 = ret[1];
      return getStringFromWasm0$1(ret[0], ret[1]);
    } finally {
      wasm$1.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
  }
};
if (Symbol.dispose) Lint$1.prototype[Symbol.dispose] = Lint$1.prototype.free;
let Linter$1 = class Linter {
  static __wrap(ptr) {
    const obj = Object.create(Linter.prototype);
    obj.__wbg_ptr = ptr;
    LinterFinalization$1.register(obj, obj.__wbg_ptr, obj);
    return obj;
  }
  __destroy_into_raw() {
    const ptr = this.__wbg_ptr;
    this.__wbg_ptr = 0;
    LinterFinalization$1.unregister(this);
    return ptr;
  }
  free() {
    const ptr = this.__destroy_into_raw();
    wasm$1.__wbg_linter_free(ptr, 0);
  }
  /**
   * Apply a suggestion from a given lint.
   * This action will be logged to the Linter's statistics.
   * @param {string} source_text
   * @param {Lint} lint
   * @param {Suggestion} suggestion
   * @returns {string}
   */
  apply_suggestion(source_text, lint, suggestion) {
    let deferred3_0;
    let deferred3_1;
    try {
      const ptr0 = passStringToWasm0$1(source_text, wasm$1.__wbindgen_malloc, wasm$1.__wbindgen_realloc);
      const len0 = WASM_VECTOR_LEN$1;
      _assertClass$1(lint, Lint$1);
      _assertClass$1(suggestion, Suggestion$1);
      const ret = wasm$1.linter_apply_suggestion(this.__wbg_ptr, ptr0, len0, lint.__wbg_ptr, suggestion.__wbg_ptr);
      var ptr2 = ret[0];
      var len2 = ret[1];
      if (ret[3]) {
        ptr2 = 0;
        len2 = 0;
        throw takeFromExternrefTable0$1(ret[2]);
      }
      deferred3_0 = ptr2;
      deferred3_1 = len2;
      return getStringFromWasm0$1(ptr2, len2);
    } finally {
      wasm$1.__wbindgen_free(deferred3_0, deferred3_1, 1);
    }
  }
  clear_ignored_lints() {
    wasm$1.linter_clear_ignored_lints(this.__wbg_ptr);
  }
  /**
   * Clear the user dictionary.
   */
  clear_words() {
    wasm$1.linter_clear_words(this.__wbg_ptr);
  }
  /**
   * Compute the context hash of a given lint.
   * @param {string} source_text
   * @param {Lint} lint
   * @returns {bigint}
   */
  context_hash(source_text, lint) {
    const ptr0 = passStringToWasm0$1(source_text, wasm$1.__wbindgen_malloc, wasm$1.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN$1;
    _assertClass$1(lint, Lint$1);
    const ret = wasm$1.linter_context_hash(this.__wbg_ptr, ptr0, len0, lint.__wbg_ptr);
    return BigInt.asUintN(64, ret);
  }
  /**
   * Export the linter's ignored lints as a privacy-respecting JSON list of hashes.
   * @returns {string}
   */
  export_ignored_lints() {
    let deferred1_0;
    let deferred1_1;
    try {
      const ret = wasm$1.linter_export_ignored_lints(this.__wbg_ptr);
      deferred1_0 = ret[0];
      deferred1_1 = ret[1];
      return getStringFromWasm0$1(ret[0], ret[1]);
    } finally {
      wasm$1.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
  }
  /**
   * Export words from the dictionary.
   * Note: this will only return words previously added by [\`Self::import_words\`].
   * @returns {string[]}
   */
  export_words() {
    const ret = wasm$1.linter_export_words(this.__wbg_ptr);
    var v1 = getArrayJsValueFromWasm0$1(ret[0], ret[1]).slice();
    wasm$1.__wbindgen_free(ret[0], ret[1] * 4, 4);
    return v1;
  }
  /**
   * @returns {string}
   */
  generate_stats_file() {
    let deferred1_0;
    let deferred1_1;
    try {
      const ret = wasm$1.linter_generate_stats_file(this.__wbg_ptr);
      deferred1_0 = ret[0];
      deferred1_1 = ret[1];
      return getStringFromWasm0$1(ret[0], ret[1]);
    } finally {
      wasm$1.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
  }
  /**
   * Get the dialect this struct was constructed for.
   * @returns {Dialect}
   */
  get_dialect() {
    const ret = wasm$1.linter_get_dialect(this.__wbg_ptr);
    return ret;
  }
  /**
   * @returns {string}
   */
  get_lint_config_as_json() {
    let deferred1_0;
    let deferred1_1;
    try {
      const ret = wasm$1.linter_get_lint_config_as_json(this.__wbg_ptr);
      deferred1_0 = ret[0];
      deferred1_1 = ret[1];
      return getStringFromWasm0$1(ret[0], ret[1]);
    } finally {
      wasm$1.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
  }
  /**
   * @returns {any}
   */
  get_lint_config_as_object() {
    const ret = wasm$1.linter_get_lint_config_as_object(this.__wbg_ptr);
    return ret;
  }
  /**
   * Get a JSON map containing the descriptions of all the linting rules, formatted as Markdown.
   * @returns {string}
   */
  get_lint_descriptions_as_json() {
    let deferred1_0;
    let deferred1_1;
    try {
      const ret = wasm$1.linter_get_lint_descriptions_as_json(this.__wbg_ptr);
      deferred1_0 = ret[0];
      deferred1_1 = ret[1];
      return getStringFromWasm0$1(ret[0], ret[1]);
    } finally {
      wasm$1.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
  }
  /**
   * Get a Record containing the descriptions of all the linting rules, formatted as Markdown.
   * @returns {any}
   */
  get_lint_descriptions_as_object() {
    const ret = wasm$1.linter_get_lint_descriptions_as_object(this.__wbg_ptr);
    return ret;
  }
  /**
   * Get a JSON map containing the descriptions of all the linting rules, formatted as HTML.
   * @returns {string}
   */
  get_lint_descriptions_html_as_json() {
    let deferred1_0;
    let deferred1_1;
    try {
      const ret = wasm$1.linter_get_lint_descriptions_html_as_json(this.__wbg_ptr);
      deferred1_0 = ret[0];
      deferred1_1 = ret[1];
      return getStringFromWasm0$1(ret[0], ret[1]);
    } finally {
      wasm$1.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
  }
  /**
   * Get a Record containing the descriptions of all the linting rules, formatted as HTML.
   * @returns {any}
   */
  get_lint_descriptions_html_as_object() {
    const ret = wasm$1.linter_get_lint_descriptions_html_as_object(this.__wbg_ptr);
    return ret;
  }
  /**
   * @returns {string}
   */
  get_structured_lint_config_as_json() {
    let deferred1_0;
    let deferred1_1;
    try {
      const ret = wasm$1.linter_get_structured_lint_config_as_json(this.__wbg_ptr);
      deferred1_0 = ret[0];
      deferred1_1 = ret[1];
      return getStringFromWasm0$1(ret[0], ret[1]);
    } finally {
      wasm$1.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
  }
  /**
   * @returns {any}
   */
  get_structured_lint_config_as_object() {
    const ret = wasm$1.linter_get_structured_lint_config_as_object(this.__wbg_ptr);
    return ret;
  }
  /**
   * Add a specific context hash to the ignored lints list.
   * @param {BigUint64Array} hashes
   */
  ignore_hashes(hashes) {
    const ptr0 = passArray64ToWasm0$1(hashes, wasm$1.__wbindgen_malloc);
    const len0 = WASM_VECTOR_LEN$1;
    wasm$1.linter_ignore_hashes(this.__wbg_ptr, ptr0, len0);
  }
  /**
   * @param {string} source_text
   * @param {Lint[]} lints
   */
  ignore_lints(source_text, lints) {
    const ptr0 = passStringToWasm0$1(source_text, wasm$1.__wbindgen_malloc, wasm$1.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN$1;
    const ptr1 = passArrayJsValueToWasm0$1(lints, wasm$1.__wbindgen_malloc);
    const len1 = WASM_VECTOR_LEN$1;
    wasm$1.linter_ignore_lints(this.__wbg_ptr, ptr0, len0, ptr1, len1);
  }
  /**
   * Import into the linter's ignored lints from a privacy-respecting JSON list of hashes.
   * @param {string} json
   */
  import_ignored_lints(json) {
    const ptr0 = passStringToWasm0$1(json, wasm$1.__wbindgen_malloc, wasm$1.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN$1;
    const ret = wasm$1.linter_import_ignored_lints(this.__wbg_ptr, ptr0, len0);
    if (ret[1]) {
      throw takeFromExternrefTable0$1(ret[0]);
    }
  }
  /**
   * @param {string} file
   */
  import_stats_file(file) {
    const ptr0 = passStringToWasm0$1(file, wasm$1.__wbindgen_malloc, wasm$1.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN$1;
    const ret = wasm$1.linter_import_stats_file(this.__wbg_ptr, ptr0, len0);
    if (ret[1]) {
      throw takeFromExternrefTable0$1(ret[0]);
    }
  }
  /**
   * Load a Weirpack from raw bytes, merging its rules into the current linter.
   * Returns test failures if any are found, and does not import in that case.
   * @param {Uint8Array} bytes
   * @returns {any}
   */
  import_weirpack(bytes) {
    const ptr0 = passArray8ToWasm0$1(bytes, wasm$1.__wbindgen_malloc);
    const len0 = WASM_VECTOR_LEN$1;
    const ret = wasm$1.linter_import_weirpack(this.__wbg_ptr, ptr0, len0);
    if (ret[2]) {
      throw takeFromExternrefTable0$1(ret[1]);
    }
    return takeFromExternrefTable0$1(ret[0]);
  }
  /**
   * Import words into the dictionary.
   * @param {string[]} additional_words
   */
  import_words(additional_words) {
    const ptr0 = passArrayJsValueToWasm0$1(additional_words, wasm$1.__wbindgen_malloc);
    const len0 = WASM_VECTOR_LEN$1;
    wasm$1.linter_import_words(this.__wbg_ptr, ptr0, len0);
  }
  /**
   * Helper method to quickly check if a plain string is likely intended to be English
   * @param {string} text
   * @returns {boolean}
   */
  is_likely_english(text) {
    const ptr0 = passStringToWasm0$1(text, wasm$1.__wbindgen_malloc, wasm$1.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN$1;
    const ret = wasm$1.linter_is_likely_english(this.__wbg_ptr, ptr0, len0);
    return ret !== 0;
  }
  /**
   * Helper method to remove non-English text from a plain English document.
   * @param {string} text
   * @returns {string}
   */
  isolate_english(text) {
    let deferred2_0;
    let deferred2_1;
    try {
      const ptr0 = passStringToWasm0$1(text, wasm$1.__wbindgen_malloc, wasm$1.__wbindgen_realloc);
      const len0 = WASM_VECTOR_LEN$1;
      const ret = wasm$1.linter_isolate_english(this.__wbg_ptr, ptr0, len0);
      deferred2_0 = ret[0];
      deferred2_1 = ret[1];
      return getStringFromWasm0$1(ret[0], ret[1]);
    } finally {
      wasm$1.__wbindgen_free(deferred2_0, deferred2_1, 1);
    }
  }
  /**
   * Perform the configured linting on the provided text.
   *
   * If the provided regex mask cannot be parsed, this method will return an empty array.
   * @param {string} text
   * @param {Language} language
   * @param {boolean} all_headings
   * @param {string | null | undefined} regex_mask
   * @param {boolean} dedup
   * @returns {Lint[]}
   */
  lint(text, language, all_headings, regex_mask, dedup) {
    const ptr0 = passStringToWasm0$1(text, wasm$1.__wbindgen_malloc, wasm$1.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN$1;
    var ptr1 = isLikeNone$1(regex_mask) ? 0 : passStringToWasm0$1(regex_mask, wasm$1.__wbindgen_malloc, wasm$1.__wbindgen_realloc);
    var len1 = WASM_VECTOR_LEN$1;
    const ret = wasm$1.linter_lint(this.__wbg_ptr, ptr0, len0, language, all_headings, ptr1, len1, dedup);
    var v3 = getArrayJsValueFromWasm0$1(ret[0], ret[1]).slice();
    wasm$1.__wbindgen_free(ret[0], ret[1] * 4, 4);
    return v3;
  }
  /**
   * Construct a new \`Linter\`.
   * Note that this can mean constructing the curated dictionary, which is the most expensive operation
   * in Harper.
   * @param {Dialect} dialect
   * @returns {Linter}
   */
  static new(dialect) {
    const ret = wasm$1.linter_new(dialect);
    return Linter.__wrap(ret);
  }
  /**
   * @param {string} text
   * @param {Language} language
   * @param {boolean} all_headings
   * @param {string | null | undefined} regex_mask
   * @param {boolean} dedup
   * @returns {OrganizedGroup[]}
   */
  organized_lints(text, language, all_headings, regex_mask, dedup) {
    const ptr0 = passStringToWasm0$1(text, wasm$1.__wbindgen_malloc, wasm$1.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN$1;
    var ptr1 = isLikeNone$1(regex_mask) ? 0 : passStringToWasm0$1(regex_mask, wasm$1.__wbindgen_malloc, wasm$1.__wbindgen_realloc);
    var len1 = WASM_VECTOR_LEN$1;
    const ret = wasm$1.linter_organized_lints(this.__wbg_ptr, ptr0, len0, language, all_headings, ptr1, len1, dedup);
    var v3 = getArrayJsValueFromWasm0$1(ret[0], ret[1]).slice();
    wasm$1.__wbindgen_free(ret[0], ret[1] * 4, 4);
    return v3;
  }
  /**
   * @param {string} json
   */
  set_lint_config_from_json(json) {
    const ptr0 = passStringToWasm0$1(json, wasm$1.__wbindgen_malloc, wasm$1.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN$1;
    const ret = wasm$1.linter_set_lint_config_from_json(this.__wbg_ptr, ptr0, len0);
    if (ret[1]) {
      throw takeFromExternrefTable0$1(ret[0]);
    }
  }
  /**
   * @param {any} object
   */
  set_lint_config_from_object(object) {
    const ret = wasm$1.linter_set_lint_config_from_object(this.__wbg_ptr, object);
    if (ret[1]) {
      throw takeFromExternrefTable0$1(ret[0]);
    }
  }
  /**
   * @param {bigint | null} [start_time]
   * @param {bigint | null} [end_time]
   * @returns {any}
   */
  summarize_stats(start_time, end_time) {
    const ret = wasm$1.linter_summarize_stats(this.__wbg_ptr, !isLikeNone$1(start_time), isLikeNone$1(start_time) ? BigInt(0) : start_time, !isLikeNone$1(end_time), isLikeNone$1(end_time) ? BigInt(0) : end_time);
    return ret;
  }
};
if (Symbol.dispose) Linter$1.prototype[Symbol.dispose] = Linter$1.prototype.free;
let OrganizedGroup$1 = class OrganizedGroup {
  static __wrap(ptr) {
    const obj = Object.create(OrganizedGroup.prototype);
    obj.__wbg_ptr = ptr;
    OrganizedGroupFinalization$1.register(obj, obj.__wbg_ptr, obj);
    return obj;
  }
  __destroy_into_raw() {
    const ptr = this.__wbg_ptr;
    this.__wbg_ptr = 0;
    OrganizedGroupFinalization$1.unregister(this);
    return ptr;
  }
  free() {
    const ptr = this.__destroy_into_raw();
    wasm$1.__wbg_organizedgroup_free(ptr, 0);
  }
  /**
   * @returns {string}
   */
  get group() {
    let deferred1_0;
    let deferred1_1;
    try {
      const ret = wasm$1.__wbg_get_organizedgroup_group(this.__wbg_ptr);
      deferred1_0 = ret[0];
      deferred1_1 = ret[1];
      return getStringFromWasm0$1(ret[0], ret[1]);
    } finally {
      wasm$1.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
  }
  /**
   * @returns {Lint[]}
   */
  get lints() {
    const ret = wasm$1.__wbg_get_organizedgroup_lints(this.__wbg_ptr);
    var v1 = getArrayJsValueFromWasm0$1(ret[0], ret[1]).slice();
    wasm$1.__wbindgen_free(ret[0], ret[1] * 4, 4);
    return v1;
  }
  /**
   * @param {string} arg0
   */
  set group(arg0) {
    const ptr0 = passStringToWasm0$1(arg0, wasm$1.__wbindgen_malloc, wasm$1.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN$1;
    wasm$1.__wbg_set_organizedgroup_group(this.__wbg_ptr, ptr0, len0);
  }
  /**
   * @param {Lint[]} arg0
   */
  set lints(arg0) {
    const ptr0 = passArrayJsValueToWasm0$1(arg0, wasm$1.__wbindgen_malloc);
    const len0 = WASM_VECTOR_LEN$1;
    wasm$1.__wbg_set_organizedgroup_lints(this.__wbg_ptr, ptr0, len0);
  }
};
if (Symbol.dispose) OrganizedGroup$1.prototype[Symbol.dispose] = OrganizedGroup$1.prototype.free;
let Span$1 = class Span {
  static __wrap(ptr) {
    const obj = Object.create(Span.prototype);
    obj.__wbg_ptr = ptr;
    SpanFinalization$1.register(obj, obj.__wbg_ptr, obj);
    return obj;
  }
  __destroy_into_raw() {
    const ptr = this.__wbg_ptr;
    this.__wbg_ptr = 0;
    SpanFinalization$1.unregister(this);
    return ptr;
  }
  free() {
    const ptr = this.__destroy_into_raw();
    wasm$1.__wbg_span_free(ptr, 0);
  }
  /**
   * @returns {number}
   */
  get end() {
    const ret = wasm$1.__wbg_get_span_end(this.__wbg_ptr);
    return ret >>> 0;
  }
  /**
   * @returns {number}
   */
  get start() {
    const ret = wasm$1.__wbg_get_span_start(this.__wbg_ptr);
    return ret >>> 0;
  }
  /**
   * @param {number} arg0
   */
  set end(arg0) {
    wasm$1.__wbg_set_span_end(this.__wbg_ptr, arg0);
  }
  /**
   * @param {number} arg0
   */
  set start(arg0) {
    wasm$1.__wbg_set_span_start(this.__wbg_ptr, arg0);
  }
  /**
   * @param {string} json
   * @returns {Span}
   */
  static from_json(json) {
    const ptr0 = passStringToWasm0$1(json, wasm$1.__wbindgen_malloc, wasm$1.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN$1;
    const ret = wasm$1.span_from_json(ptr0, len0);
    if (ret[2]) {
      throw takeFromExternrefTable0$1(ret[1]);
    }
    return Span.__wrap(ret[0]);
  }
  /**
   * @returns {boolean}
   */
  is_empty() {
    const ret = wasm$1.span_is_empty(this.__wbg_ptr);
    return ret !== 0;
  }
  /**
   * @returns {number}
   */
  len() {
    const ret = wasm$1.span_len(this.__wbg_ptr);
    return ret >>> 0;
  }
  /**
   * @param {number} start
   * @param {number} end
   * @returns {Span}
   */
  static new(start, end) {
    const ret = wasm$1.span_new(start, end);
    return Span.__wrap(ret);
  }
  /**
   * @returns {string}
   */
  to_json() {
    let deferred1_0;
    let deferred1_1;
    try {
      const ret = wasm$1.span_to_json(this.__wbg_ptr);
      deferred1_0 = ret[0];
      deferred1_1 = ret[1];
      return getStringFromWasm0$1(ret[0], ret[1]);
    } finally {
      wasm$1.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
  }
};
if (Symbol.dispose) Span$1.prototype[Symbol.dispose] = Span$1.prototype.free;
let Suggestion$1 = class Suggestion {
  static __wrap(ptr) {
    const obj = Object.create(Suggestion.prototype);
    obj.__wbg_ptr = ptr;
    SuggestionFinalization$1.register(obj, obj.__wbg_ptr, obj);
    return obj;
  }
  __destroy_into_raw() {
    const ptr = this.__wbg_ptr;
    this.__wbg_ptr = 0;
    SuggestionFinalization$1.unregister(this);
    return ptr;
  }
  free() {
    const ptr = this.__destroy_into_raw();
    wasm$1.__wbg_suggestion_free(ptr, 0);
  }
  /**
   * @param {string} json
   * @returns {Suggestion}
   */
  static from_json(json) {
    const ptr0 = passStringToWasm0$1(json, wasm$1.__wbindgen_malloc, wasm$1.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN$1;
    const ret = wasm$1.suggestion_from_json(ptr0, len0);
    if (ret[2]) {
      throw takeFromExternrefTable0$1(ret[1]);
    }
    return Suggestion.__wrap(ret[0]);
  }
  /**
   * Get the text that is going to replace the problematic section.
   * If [\`Self::kind\`] is \`SuggestionKind::Remove\`, this will return an empty
   * string.
   * @returns {string}
   */
  get_replacement_text() {
    let deferred1_0;
    let deferred1_1;
    try {
      const ret = wasm$1.suggestion_get_replacement_text(this.__wbg_ptr);
      deferred1_0 = ret[0];
      deferred1_1 = ret[1];
      return getStringFromWasm0$1(ret[0], ret[1]);
    } finally {
      wasm$1.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
  }
  /**
   * @returns {SuggestionKind}
   */
  kind() {
    const ret = wasm$1.suggestion_kind(this.__wbg_ptr);
    return ret;
  }
  /**
   * @returns {string}
   */
  to_json() {
    let deferred1_0;
    let deferred1_1;
    try {
      const ret = wasm$1.suggestion_to_json(this.__wbg_ptr);
      deferred1_0 = ret[0];
      deferred1_1 = ret[1];
      return getStringFromWasm0$1(ret[0], ret[1]);
    } finally {
      wasm$1.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
  }
};
if (Symbol.dispose) Suggestion$1.prototype[Symbol.dispose] = Suggestion$1.prototype.free;
const SuggestionKind$1 = Object.freeze({
  /**
   * Replace the problematic text.
   */
  Replace: 0,
  "0": "Replace",
  /**
   * Remove the problematic text.
   */
  Remove: 1,
  "1": "Remove",
  /**
   * Insert additional text after the error.
   */
  InsertAfter: 2,
  "2": "InsertAfter"
});
function get_default_lint_config$1() {
  const ret = wasm$1.get_default_lint_config();
  return ret;
}
function get_default_lint_config_as_json$1() {
  let deferred1_0;
  let deferred1_1;
  try {
    const ret = wasm$1.get_default_lint_config_as_json();
    deferred1_0 = ret[0];
    deferred1_1 = ret[1];
    return getStringFromWasm0$1(ret[0], ret[1]);
  } finally {
    wasm$1.__wbindgen_free(deferred1_0, deferred1_1, 1);
  }
}
function setup$1() {
  wasm$1.setup();
}
function to_title_case$1(text) {
  let deferred2_0;
  let deferred2_1;
  try {
    const ptr0 = passStringToWasm0$1(text, wasm$1.__wbindgen_malloc, wasm$1.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN$1;
    const ret = wasm$1.to_title_case(ptr0, len0);
    deferred2_0 = ret[0];
    deferred2_1 = ret[1];
    return getStringFromWasm0$1(ret[0], ret[1]);
  } finally {
    wasm$1.__wbindgen_free(deferred2_0, deferred2_1, 1);
  }
}
function __wbg_get_imports$1() {
  const import0 = {
    __proto__: null,
    __wbg_Error_bce6d499ff0a4aff: function(arg0, arg1) {
      const ret = Error(getStringFromWasm0$1(arg0, arg1));
      return ret;
    },
    __wbg_String_8564e559799eccda: function(arg0, arg1) {
      const ret = String(arg1);
      const ptr1 = passStringToWasm0$1(ret, wasm$1.__wbindgen_malloc, wasm$1.__wbindgen_realloc);
      const len1 = WASM_VECTOR_LEN$1;
      getDataViewMemory0$1().setInt32(arg0 + 4 * 1, len1, true);
      getDataViewMemory0$1().setInt32(arg0 + 4 * 0, ptr1, true);
    },
    __wbg___wbindgen_boolean_get_2304fb8c853028c8: function(arg0) {
      const v = arg0;
      const ret = typeof v === "boolean" ? v : void 0;
      return isLikeNone$1(ret) ? 16777215 : ret ? 1 : 0;
    },
    __wbg___wbindgen_debug_string_edece8177ad01481: function(arg0, arg1) {
      const ret = debugString$1(arg1);
      const ptr1 = passStringToWasm0$1(ret, wasm$1.__wbindgen_malloc, wasm$1.__wbindgen_realloc);
      const len1 = WASM_VECTOR_LEN$1;
      getDataViewMemory0$1().setInt32(arg0 + 4 * 1, len1, true);
      getDataViewMemory0$1().setInt32(arg0 + 4 * 0, ptr1, true);
    },
    __wbg___wbindgen_is_function_5cd60d5cf78b4eef: function(arg0) {
      const ret = typeof arg0 === "function";
      return ret;
    },
    __wbg___wbindgen_is_object_b4593df85baada48: function(arg0) {
      const val = arg0;
      const ret = typeof val === "object" && val !== null;
      return ret;
    },
    __wbg___wbindgen_is_string_dde0fd9020db4434: function(arg0) {
      const ret = typeof arg0 === "string";
      return ret;
    },
    __wbg___wbindgen_jsval_loose_eq_0ad77b7717db155c: function(arg0, arg1) {
      const ret = arg0 == arg1;
      return ret;
    },
    __wbg___wbindgen_number_get_f73a1244370fcc2c: function(arg0, arg1) {
      const obj = arg1;
      const ret = typeof obj === "number" ? obj : void 0;
      getDataViewMemory0$1().setFloat64(arg0 + 8 * 1, isLikeNone$1(ret) ? 0 : ret, true);
      getDataViewMemory0$1().setInt32(arg0 + 4 * 0, !isLikeNone$1(ret), true);
    },
    __wbg___wbindgen_string_get_d109740c0d18f4d7: function(arg0, arg1) {
      const obj = arg1;
      const ret = typeof obj === "string" ? obj : void 0;
      var ptr1 = isLikeNone$1(ret) ? 0 : passStringToWasm0$1(ret, wasm$1.__wbindgen_malloc, wasm$1.__wbindgen_realloc);
      var len1 = WASM_VECTOR_LEN$1;
      getDataViewMemory0$1().setInt32(arg0 + 4 * 1, len1, true);
      getDataViewMemory0$1().setInt32(arg0 + 4 * 0, ptr1, true);
    },
    __wbg___wbindgen_throw_9c31b086c2b26051: function(arg0, arg1) {
      throw new Error(getStringFromWasm0$1(arg0, arg1));
    },
    __wbg_call_13665d9f14390edc: function() {
      return handleError$1(function(arg0, arg1) {
        const ret = arg0.call(arg1);
        return ret;
      }, arguments);
    },
    __wbg_done_54b8da57023b7ed2: function(arg0) {
      const ret = arg0.done;
      return ret;
    },
    __wbg_entries_564a7e8b1e54ede5: function(arg0) {
      const ret = Object.entries(arg0);
      return ret;
    },
    __wbg_error_a6fa202b58aa1cd3: function(arg0, arg1) {
      let deferred0_0;
      let deferred0_1;
      try {
        deferred0_0 = arg0;
        deferred0_1 = arg1;
        console.error(getStringFromWasm0$1(arg0, arg1));
      } finally {
        wasm$1.__wbindgen_free(deferred0_0, deferred0_1, 1);
      }
    },
    __wbg_getRandomValues_3f44b700395062e5: function() {
      return handleError$1(function(arg0, arg1) {
        globalThis.crypto.getRandomValues(getArrayU8FromWasm0$1(arg0, arg1));
      }, arguments);
    },
    __wbg_getRandomValues_d49329ff89a07af1: function() {
      return handleError$1(function(arg0, arg1) {
        globalThis.crypto.getRandomValues(getArrayU8FromWasm0$1(arg0, arg1));
      }, arguments);
    },
    __wbg_getTime_09f1dd40a44edb30: function(arg0) {
      const ret = arg0.getTime();
      return ret;
    },
    __wbg_get_3e9a707ab7d352eb: function() {
      return handleError$1(function(arg0, arg1) {
        const ret = Reflect.get(arg0, arg1);
        return ret;
      }, arguments);
    },
    __wbg_get_98fdf51d029a75eb: function(arg0, arg1) {
      const ret = arg0[arg1 >>> 0];
      return ret;
    },
    __wbg_get_unchecked_1dfe6d05ad91d9b7: function(arg0, arg1) {
      const ret = arg0[arg1 >>> 0];
      return ret;
    },
    __wbg_instanceof_ArrayBuffer_53db37b06f6b9afe: function(arg0) {
      let result;
      try {
        result = arg0 instanceof ArrayBuffer;
      } catch (_) {
        result = false;
      }
      const ret = result;
      return ret;
    },
    __wbg_instanceof_Uint8Array_abd07d4bd221d50b: function(arg0) {
      let result;
      try {
        result = arg0 instanceof Uint8Array;
      } catch (_) {
        result = false;
      }
      const ret = result;
      return ret;
    },
    __wbg_iterator_1441b47f341dc34f: function() {
      const ret = Symbol.iterator;
      return ret;
    },
    __wbg_length_2591a0f4f659a55c: function(arg0) {
      const ret = arg0.length;
      return ret;
    },
    __wbg_length_56fcd3e2b7e0299d: function(arg0) {
      const ret = arg0.length;
      return ret;
    },
    __wbg_lint_new: function(arg0) {
      const ret = Lint$1.__wrap(arg0);
      return ret;
    },
    __wbg_lint_unwrap: function(arg0) {
      const ret = Lint$1.__unwrap(arg0);
      return ret;
    },
    __wbg_log_0c201ade58bb55e1: function(arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7) {
      let deferred0_0;
      let deferred0_1;
      try {
        deferred0_0 = arg0;
        deferred0_1 = arg1;
        console.log(getStringFromWasm0$1(arg0, arg1), getStringFromWasm0$1(arg2, arg3), getStringFromWasm0$1(arg4, arg5), getStringFromWasm0$1(arg6, arg7));
      } finally {
        wasm$1.__wbindgen_free(deferred0_0, deferred0_1, 1);
      }
    },
    __wbg_log_ce2c4456b290c5e7: function(arg0, arg1) {
      let deferred0_0;
      let deferred0_1;
      try {
        deferred0_0 = arg0;
        deferred0_1 = arg1;
        console.log(getStringFromWasm0$1(arg0, arg1));
      } finally {
        wasm$1.__wbindgen_free(deferred0_0, deferred0_1, 1);
      }
    },
    __wbg_mark_b4d943f3bc2d2404: function(arg0, arg1) {
      performance.mark(getStringFromWasm0$1(arg0, arg1));
    },
    __wbg_measure_84362959e621a2c1: function() {
      return handleError$1(function(arg0, arg1, arg2, arg3) {
        let deferred0_0;
        let deferred0_1;
        let deferred1_0;
        let deferred1_1;
        try {
          deferred0_0 = arg0;
          deferred0_1 = arg1;
          deferred1_0 = arg2;
          deferred1_1 = arg3;
          performance.measure(getStringFromWasm0$1(arg0, arg1), getStringFromWasm0$1(arg2, arg3));
        } finally {
          wasm$1.__wbindgen_free(deferred0_0, deferred0_1, 1);
          wasm$1.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
      }, arguments);
    },
    __wbg_new_02d162bc6cf02f60: function() {
      const ret = new Object();
      return ret;
    },
    __wbg_new_070df68d66325372: function() {
      const ret = /* @__PURE__ */ new Map();
      return ret;
    },
    __wbg_new_0_2722fcdb71a888a6: function() {
      const ret = /* @__PURE__ */ new Date();
      return ret;
    },
    __wbg_new_227d7c05414eb861: function() {
      const ret = new Error();
      return ret;
    },
    __wbg_new_310879b66b6e95e1: function() {
      const ret = new Array();
      return ret;
    },
    __wbg_new_7ddec6de44ff8f5d: function(arg0) {
      const ret = new Uint8Array(arg0);
      return ret;
    },
    __wbg_next_2a4e19f4f5083b0f: function(arg0) {
      const ret = arg0.next;
      return ret;
    },
    __wbg_next_6429a146bf756f93: function() {
      return handleError$1(function(arg0) {
        const ret = arg0.next();
        return ret;
      }, arguments);
    },
    __wbg_organizedgroup_new: function(arg0) {
      const ret = OrganizedGroup$1.__wrap(arg0);
      return ret;
    },
    __wbg_prototypesetcall_5f9bdc8d75e07276: function(arg0, arg1, arg2) {
      Uint8Array.prototype.set.call(getArrayU8FromWasm0$1(arg0, arg1), arg2);
    },
    __wbg_set_6be42768c690e380: function(arg0, arg1, arg2) {
      arg0[arg1] = arg2;
    },
    __wbg_set_78ea6a19f4818587: function(arg0, arg1, arg2) {
      arg0[arg1 >>> 0] = arg2;
    },
    __wbg_set_facb7a5914e0fa39: function(arg0, arg1, arg2) {
      const ret = arg0.set(arg1, arg2);
      return ret;
    },
    __wbg_stack_3b0d974bbf31e44f: function(arg0, arg1) {
      const ret = arg1.stack;
      const ptr1 = passStringToWasm0$1(ret, wasm$1.__wbindgen_malloc, wasm$1.__wbindgen_realloc);
      const len1 = WASM_VECTOR_LEN$1;
      getDataViewMemory0$1().setInt32(arg0 + 4 * 1, len1, true);
      getDataViewMemory0$1().setInt32(arg0 + 4 * 0, ptr1, true);
    },
    __wbg_suggestion_new: function(arg0) {
      const ret = Suggestion$1.__wrap(arg0);
      return ret;
    },
    __wbg_value_9cc0518af87a489c: function(arg0) {
      const ret = arg0.value;
      return ret;
    },
    __wbindgen_cast_0000000000000001: function(arg0) {
      const ret = arg0;
      return ret;
    },
    __wbindgen_cast_0000000000000002: function(arg0, arg1) {
      const ret = getStringFromWasm0$1(arg0, arg1);
      return ret;
    },
    __wbindgen_init_externref_table: function() {
      const table = wasm$1.__wbindgen_externrefs;
      const offset = table.grow(4);
      table.set(0, void 0);
      table.set(offset + 0, void 0);
      table.set(offset + 1, null);
      table.set(offset + 2, true);
      table.set(offset + 3, false);
    }
  };
  return {
    __proto__: null,
    "./harper_wasm_slim_bg.js": import0
  };
}
const LintFinalization$1 = typeof FinalizationRegistry === "undefined" ? { register: () => {
}, unregister: () => {
} } : new FinalizationRegistry((ptr) => wasm$1.__wbg_lint_free(ptr, 1));
const LinterFinalization$1 = typeof FinalizationRegistry === "undefined" ? { register: () => {
}, unregister: () => {
} } : new FinalizationRegistry((ptr) => wasm$1.__wbg_linter_free(ptr, 1));
const OrganizedGroupFinalization$1 = typeof FinalizationRegistry === "undefined" ? { register: () => {
}, unregister: () => {
} } : new FinalizationRegistry((ptr) => wasm$1.__wbg_organizedgroup_free(ptr, 1));
const SpanFinalization$1 = typeof FinalizationRegistry === "undefined" ? { register: () => {
}, unregister: () => {
} } : new FinalizationRegistry((ptr) => wasm$1.__wbg_span_free(ptr, 1));
const SuggestionFinalization$1 = typeof FinalizationRegistry === "undefined" ? { register: () => {
}, unregister: () => {
} } : new FinalizationRegistry((ptr) => wasm$1.__wbg_suggestion_free(ptr, 1));
function addToExternrefTable0$1(obj) {
  const idx = wasm$1.__externref_table_alloc();
  wasm$1.__wbindgen_externrefs.set(idx, obj);
  return idx;
}
function _assertClass$1(instance, klass) {
  if (!(instance instanceof klass)) {
    throw new Error(\`expected instance of \${klass.name}\`);
  }
}
function debugString$1(val) {
  const type = typeof val;
  if (type == "number" || type == "boolean" || val == null) {
    return \`\${val}\`;
  }
  if (type == "string") {
    return \`"\${val}"\`;
  }
  if (type == "symbol") {
    const description = val.description;
    if (description == null) {
      return "Symbol";
    } else {
      return \`Symbol(\${description})\`;
    }
  }
  if (type == "function") {
    const name = val.name;
    if (typeof name == "string" && name.length > 0) {
      return \`Function(\${name})\`;
    } else {
      return "Function";
    }
  }
  if (Array.isArray(val)) {
    const length = val.length;
    let debug = "[";
    if (length > 0) {
      debug += debugString$1(val[0]);
    }
    for (let i = 1; i < length; i++) {
      debug += ", " + debugString$1(val[i]);
    }
    debug += "]";
    return debug;
  }
  const builtInMatches = /\\[object ([^\\]]+)\\]/.exec(toString.call(val));
  let className;
  if (builtInMatches && builtInMatches.length > 1) {
    className = builtInMatches[1];
  } else {
    return toString.call(val);
  }
  if (className == "Object") {
    try {
      return "Object(" + JSON.stringify(val) + ")";
    } catch (_) {
      return "Object";
    }
  }
  if (val instanceof Error) {
    return \`\${val.name}: \${val.message}
\${val.stack}\`;
  }
  return className;
}
function getArrayJsValueFromWasm0$1(ptr, len) {
  ptr = ptr >>> 0;
  const mem = getDataViewMemory0$1();
  const result = [];
  for (let i = ptr; i < ptr + 4 * len; i += 4) {
    result.push(wasm$1.__wbindgen_externrefs.get(mem.getUint32(i, true)));
  }
  wasm$1.__externref_drop_slice(ptr, len);
  return result;
}
function getArrayU8FromWasm0$1(ptr, len) {
  ptr = ptr >>> 0;
  return getUint8ArrayMemory0$1().subarray(ptr / 1, ptr / 1 + len);
}
let cachedBigUint64ArrayMemory0$1 = null;
function getBigUint64ArrayMemory0$1() {
  if (cachedBigUint64ArrayMemory0$1 === null || cachedBigUint64ArrayMemory0$1.byteLength === 0) {
    cachedBigUint64ArrayMemory0$1 = new BigUint64Array(wasm$1.memory.buffer);
  }
  return cachedBigUint64ArrayMemory0$1;
}
let cachedDataViewMemory0$1 = null;
function getDataViewMemory0$1() {
  if (cachedDataViewMemory0$1 === null || cachedDataViewMemory0$1.buffer.detached === true || cachedDataViewMemory0$1.buffer.detached === void 0 && cachedDataViewMemory0$1.buffer !== wasm$1.memory.buffer) {
    cachedDataViewMemory0$1 = new DataView(wasm$1.memory.buffer);
  }
  return cachedDataViewMemory0$1;
}
function getStringFromWasm0$1(ptr, len) {
  return decodeText$1(ptr >>> 0, len);
}
let cachedUint8ArrayMemory0$1 = null;
function getUint8ArrayMemory0$1() {
  if (cachedUint8ArrayMemory0$1 === null || cachedUint8ArrayMemory0$1.byteLength === 0) {
    cachedUint8ArrayMemory0$1 = new Uint8Array(wasm$1.memory.buffer);
  }
  return cachedUint8ArrayMemory0$1;
}
function handleError$1(f, args) {
  try {
    return f.apply(this, args);
  } catch (e) {
    const idx = addToExternrefTable0$1(e);
    wasm$1.__wbindgen_exn_store(idx);
  }
}
function isLikeNone$1(x) {
  return x === void 0 || x === null;
}
function passArray64ToWasm0$1(arg, malloc) {
  const ptr = malloc(arg.length * 8, 8) >>> 0;
  getBigUint64ArrayMemory0$1().set(arg, ptr / 8);
  WASM_VECTOR_LEN$1 = arg.length;
  return ptr;
}
function passArray8ToWasm0$1(arg, malloc) {
  const ptr = malloc(arg.length * 1, 1) >>> 0;
  getUint8ArrayMemory0$1().set(arg, ptr / 1);
  WASM_VECTOR_LEN$1 = arg.length;
  return ptr;
}
function passArrayJsValueToWasm0$1(array, malloc) {
  const ptr = malloc(array.length * 4, 4) >>> 0;
  for (let i = 0; i < array.length; i++) {
    const add = addToExternrefTable0$1(array[i]);
    getDataViewMemory0$1().setUint32(ptr + 4 * i, add, true);
  }
  WASM_VECTOR_LEN$1 = array.length;
  return ptr;
}
function passStringToWasm0$1(arg, malloc, realloc) {
  if (realloc === void 0) {
    const buf = cachedTextEncoder$1.encode(arg);
    const ptr2 = malloc(buf.length, 1) >>> 0;
    getUint8ArrayMemory0$1().subarray(ptr2, ptr2 + buf.length).set(buf);
    WASM_VECTOR_LEN$1 = buf.length;
    return ptr2;
  }
  let len = arg.length;
  let ptr = malloc(len, 1) >>> 0;
  const mem = getUint8ArrayMemory0$1();
  let offset = 0;
  for (; offset < len; offset++) {
    const code = arg.charCodeAt(offset);
    if (code > 127) break;
    mem[ptr + offset] = code;
  }
  if (offset !== len) {
    if (offset !== 0) {
      arg = arg.slice(offset);
    }
    ptr = realloc(ptr, len, len = offset + arg.length * 3, 1) >>> 0;
    const view = getUint8ArrayMemory0$1().subarray(ptr + offset, ptr + len);
    const ret = cachedTextEncoder$1.encodeInto(arg, view);
    offset += ret.written;
    ptr = realloc(ptr, len, offset, 1) >>> 0;
  }
  WASM_VECTOR_LEN$1 = offset;
  return ptr;
}
function takeFromExternrefTable0$1(idx) {
  const value = wasm$1.__wbindgen_externrefs.get(idx);
  wasm$1.__externref_table_dealloc(idx);
  return value;
}
let cachedTextDecoder$1 = new TextDecoder("utf-8", { ignoreBOM: true, fatal: true });
cachedTextDecoder$1.decode();
const MAX_SAFARI_DECODE_BYTES$1 = 2146435072;
let numBytesDecoded$1 = 0;
function decodeText$1(ptr, len) {
  numBytesDecoded$1 += len;
  if (numBytesDecoded$1 >= MAX_SAFARI_DECODE_BYTES$1) {
    cachedTextDecoder$1 = new TextDecoder("utf-8", { ignoreBOM: true, fatal: true });
    cachedTextDecoder$1.decode();
    numBytesDecoded$1 = len;
  }
  return cachedTextDecoder$1.decode(getUint8ArrayMemory0$1().subarray(ptr, ptr + len));
}
const cachedTextEncoder$1 = new TextEncoder();
if (!("encodeInto" in cachedTextEncoder$1)) {
  cachedTextEncoder$1.encodeInto = function(arg, view) {
    const buf = cachedTextEncoder$1.encode(arg);
    view.set(buf);
    return {
      read: arg.length,
      written: buf.length
    };
  };
}
let WASM_VECTOR_LEN$1 = 0;
let wasm$1;
function __wbg_finalize_init$1(instance, module) {
  wasm$1 = instance.exports;
  cachedBigUint64ArrayMemory0$1 = null;
  cachedDataViewMemory0$1 = null;
  cachedUint8ArrayMemory0$1 = null;
  wasm$1.__wbindgen_start();
  return wasm$1;
}
async function __wbg_load$1(module, imports) {
  if (typeof Response === "function" && module instanceof Response) {
    if (typeof WebAssembly.instantiateStreaming === "function") {
      try {
        return await WebAssembly.instantiateStreaming(module, imports);
      } catch (e) {
        const validResponse = module.ok && expectedResponseType(module.type);
        if (validResponse && module.headers.get("Content-Type") !== "application/wasm") {
          console.warn("\`WebAssembly.instantiateStreaming\` failed because your server does not serve Wasm with \`application/wasm\` MIME type. Falling back to \`WebAssembly.instantiate\` which is slower. Original error:\\n", e);
        } else {
          throw e;
        }
      }
    }
    const bytes = await module.arrayBuffer();
    return await WebAssembly.instantiate(bytes, imports);
  } else {
    const instance = await WebAssembly.instantiate(module, imports);
    if (instance instanceof WebAssembly.Instance) {
      return { instance, module };
    } else {
      return instance;
    }
  }
  function expectedResponseType(type) {
    switch (type) {
      case "basic":
      case "cors":
      case "default":
        return true;
    }
    return false;
  }
}
function initSync$1(module) {
  if (wasm$1 !== void 0) return wasm$1;
  if (module !== void 0) {
    if (Object.getPrototypeOf(module) === Object.prototype) {
      ({ module } = module);
    } else {
      console.warn("using deprecated parameters for \`initSync()\`; pass a single object instead");
    }
  }
  const imports = __wbg_get_imports$1();
  if (!(module instanceof WebAssembly.Module)) {
    module = new WebAssembly.Module(module);
  }
  const instance = new WebAssembly.Instance(module, imports);
  return __wbg_finalize_init$1(instance);
}
async function __wbg_init$1(module_or_path) {
  if (wasm$1 !== void 0) return wasm$1;
  if (module_or_path !== void 0) {
    if (Object.getPrototypeOf(module_or_path) === Object.prototype) {
      ({ module_or_path } = module_or_path);
    } else {
      console.warn("using deprecated parameters for the initialization function; pass a single object instead");
    }
  }
  if (module_or_path === void 0) {
    module_or_path = new URL();
  }
  const imports = __wbg_get_imports$1();
  if (typeof module_or_path === "string" || typeof Request === "function" && module_or_path instanceof Request || typeof URL === "function" && module_or_path instanceof URL) {
    module_or_path = fetch(module_or_path);
  }
  const { instance, module } = await __wbg_load$1(await module_or_path, imports);
  return __wbg_finalize_init$1(instance);
}
var defaultGlue = /* @__PURE__ */ Object.freeze({
  __proto__: null,
  Dialect: Dialect$1,
  Language: Language$1,
  Lint: Lint$1,
  Linter: Linter$1,
  OrganizedGroup: OrganizedGroup$1,
  Span: Span$1,
  Suggestion: Suggestion$1,
  SuggestionKind: SuggestionKind$1,
  default: __wbg_init$1,
  get_default_lint_config: get_default_lint_config$1,
  get_default_lint_config_as_json: get_default_lint_config_as_json$1,
  initSync: initSync$1,
  setup: setup$1,
  to_title_case: to_title_case$1
});
const Dialect = Object.freeze({
  American: 0,
  "0": "American",
  British: 1,
  "1": "British",
  Australian: 2,
  "2": "Australian",
  Canadian: 3,
  "3": "Canadian",
  Indian: 4,
  "4": "Indian"
});
const Language = Object.freeze({
  Plain: 0,
  "0": "Plain",
  Markdown: 1,
  "1": "Markdown",
  Typst: 2,
  "2": "Typst"
});
class Lint2 {
  static __wrap(ptr) {
    const obj = Object.create(Lint2.prototype);
    obj.__wbg_ptr = ptr;
    LintFinalization.register(obj, obj.__wbg_ptr, obj);
    return obj;
  }
  static __unwrap(jsValue) {
    if (!(jsValue instanceof Lint2)) {
      return 0;
    }
    return jsValue.__destroy_into_raw();
  }
  __destroy_into_raw() {
    const ptr = this.__wbg_ptr;
    this.__wbg_ptr = 0;
    LintFinalization.unregister(this);
    return ptr;
  }
  free() {
    const ptr = this.__destroy_into_raw();
    wasm.__wbg_lint_free(ptr, 0);
  }
  /**
   * @param {string} json
   * @returns {Lint}
   */
  static from_json(json) {
    const ptr0 = passStringToWasm0(json, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    const ret = wasm.lint_from_json(ptr0, len0);
    if (ret[2]) {
      throw takeFromExternrefTable0(ret[1]);
    }
    return Lint2.__wrap(ret[0]);
  }
  /**
   * Get the content of the source material pointed to by [\`Self::span\`]
   * @returns {string}
   */
  get_problem_text() {
    let deferred1_0;
    let deferred1_1;
    try {
      const ret = wasm.lint_get_problem_text(this.__wbg_ptr);
      deferred1_0 = ret[0];
      deferred1_1 = ret[1];
      return getStringFromWasm0(ret[0], ret[1]);
    } finally {
      wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
  }
  /**
   * Get a string representing the general category of the lint.
   * @returns {string}
   */
  lint_kind() {
    let deferred1_0;
    let deferred1_1;
    try {
      const ret = wasm.lint_lint_kind(this.__wbg_ptr);
      deferred1_0 = ret[0];
      deferred1_1 = ret[1];
      return getStringFromWasm0(ret[0], ret[1]);
    } finally {
      wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
  }
  /**
   * Get a string representing the general category of the lint.
   * @returns {string}
   */
  lint_kind_pretty() {
    let deferred1_0;
    let deferred1_1;
    try {
      const ret = wasm.lint_lint_kind_pretty(this.__wbg_ptr);
      deferred1_0 = ret[0];
      deferred1_1 = ret[1];
      return getStringFromWasm0(ret[0], ret[1]);
    } finally {
      wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
  }
  /**
   * Get a description of the error.
   * @returns {string}
   */
  message() {
    let deferred1_0;
    let deferred1_1;
    try {
      const ret = wasm.lint_message(this.__wbg_ptr);
      deferred1_0 = ret[0];
      deferred1_1 = ret[1];
      return getStringFromWasm0(ret[0], ret[1]);
    } finally {
      wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
  }
  /**
   * Get a description of the error as HTML.
   * @returns {string}
   */
  message_html() {
    let deferred1_0;
    let deferred1_1;
    try {
      const ret = wasm.lint_message_html(this.__wbg_ptr);
      deferred1_0 = ret[0];
      deferred1_1 = ret[1];
      return getStringFromWasm0(ret[0], ret[1]);
    } finally {
      wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
  }
  /**
   * Get the location of the problematic text.
   * @returns {Span}
   */
  span() {
    const ret = wasm.lint_span(this.__wbg_ptr);
    return Span2.__wrap(ret);
  }
  /**
   * Equivalent to calling \`.length\` on the result of \`suggestions()\`.
   * @returns {number}
   */
  suggestion_count() {
    const ret = wasm.lint_suggestion_count(this.__wbg_ptr);
    return ret >>> 0;
  }
  /**
   * Get an array of any suggestions that may resolve the issue.
   * @returns {Suggestion[]}
   */
  suggestions() {
    const ret = wasm.lint_suggestions(this.__wbg_ptr);
    var v1 = getArrayJsValueFromWasm0(ret[0], ret[1]).slice();
    wasm.__wbindgen_free(ret[0], ret[1] * 4, 4);
    return v1;
  }
  /**
   * @returns {string}
   */
  to_json() {
    let deferred1_0;
    let deferred1_1;
    try {
      const ret = wasm.lint_to_json(this.__wbg_ptr);
      deferred1_0 = ret[0];
      deferred1_1 = ret[1];
      return getStringFromWasm0(ret[0], ret[1]);
    } finally {
      wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
  }
}
if (Symbol.dispose) Lint2.prototype[Symbol.dispose] = Lint2.prototype.free;
class Linter2 {
  static __wrap(ptr) {
    const obj = Object.create(Linter2.prototype);
    obj.__wbg_ptr = ptr;
    LinterFinalization.register(obj, obj.__wbg_ptr, obj);
    return obj;
  }
  __destroy_into_raw() {
    const ptr = this.__wbg_ptr;
    this.__wbg_ptr = 0;
    LinterFinalization.unregister(this);
    return ptr;
  }
  free() {
    const ptr = this.__destroy_into_raw();
    wasm.__wbg_linter_free(ptr, 0);
  }
  /**
   * Apply a suggestion from a given lint.
   * This action will be logged to the Linter's statistics.
   * @param {string} source_text
   * @param {Lint} lint
   * @param {Suggestion} suggestion
   * @returns {string}
   */
  apply_suggestion(source_text, lint, suggestion) {
    let deferred3_0;
    let deferred3_1;
    try {
      const ptr0 = passStringToWasm0(source_text, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
      const len0 = WASM_VECTOR_LEN;
      _assertClass(lint, Lint2);
      _assertClass(suggestion, Suggestion2);
      const ret = wasm.linter_apply_suggestion(this.__wbg_ptr, ptr0, len0, lint.__wbg_ptr, suggestion.__wbg_ptr);
      var ptr2 = ret[0];
      var len2 = ret[1];
      if (ret[3]) {
        ptr2 = 0;
        len2 = 0;
        throw takeFromExternrefTable0(ret[2]);
      }
      deferred3_0 = ptr2;
      deferred3_1 = len2;
      return getStringFromWasm0(ptr2, len2);
    } finally {
      wasm.__wbindgen_free(deferred3_0, deferred3_1, 1);
    }
  }
  clear_ignored_lints() {
    wasm.linter_clear_ignored_lints(this.__wbg_ptr);
  }
  /**
   * Clear the user dictionary.
   */
  clear_words() {
    wasm.linter_clear_words(this.__wbg_ptr);
  }
  /**
   * Compute the context hash of a given lint.
   * @param {string} source_text
   * @param {Lint} lint
   * @returns {bigint}
   */
  context_hash(source_text, lint) {
    const ptr0 = passStringToWasm0(source_text, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    _assertClass(lint, Lint2);
    const ret = wasm.linter_context_hash(this.__wbg_ptr, ptr0, len0, lint.__wbg_ptr);
    return BigInt.asUintN(64, ret);
  }
  /**
   * Export the linter's ignored lints as a privacy-respecting JSON list of hashes.
   * @returns {string}
   */
  export_ignored_lints() {
    let deferred1_0;
    let deferred1_1;
    try {
      const ret = wasm.linter_export_ignored_lints(this.__wbg_ptr);
      deferred1_0 = ret[0];
      deferred1_1 = ret[1];
      return getStringFromWasm0(ret[0], ret[1]);
    } finally {
      wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
  }
  /**
   * Export words from the dictionary.
   * Note: this will only return words previously added by [\`Self::import_words\`].
   * @returns {string[]}
   */
  export_words() {
    const ret = wasm.linter_export_words(this.__wbg_ptr);
    var v1 = getArrayJsValueFromWasm0(ret[0], ret[1]).slice();
    wasm.__wbindgen_free(ret[0], ret[1] * 4, 4);
    return v1;
  }
  /**
   * @returns {string}
   */
  generate_stats_file() {
    let deferred1_0;
    let deferred1_1;
    try {
      const ret = wasm.linter_generate_stats_file(this.__wbg_ptr);
      deferred1_0 = ret[0];
      deferred1_1 = ret[1];
      return getStringFromWasm0(ret[0], ret[1]);
    } finally {
      wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
  }
  /**
   * Get the dialect this struct was constructed for.
   * @returns {Dialect}
   */
  get_dialect() {
    const ret = wasm.linter_get_dialect(this.__wbg_ptr);
    return ret;
  }
  /**
   * @returns {string}
   */
  get_lint_config_as_json() {
    let deferred1_0;
    let deferred1_1;
    try {
      const ret = wasm.linter_get_lint_config_as_json(this.__wbg_ptr);
      deferred1_0 = ret[0];
      deferred1_1 = ret[1];
      return getStringFromWasm0(ret[0], ret[1]);
    } finally {
      wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
  }
  /**
   * @returns {any}
   */
  get_lint_config_as_object() {
    const ret = wasm.linter_get_lint_config_as_object(this.__wbg_ptr);
    return ret;
  }
  /**
   * Get a JSON map containing the descriptions of all the linting rules, formatted as Markdown.
   * @returns {string}
   */
  get_lint_descriptions_as_json() {
    let deferred1_0;
    let deferred1_1;
    try {
      const ret = wasm.linter_get_lint_descriptions_as_json(this.__wbg_ptr);
      deferred1_0 = ret[0];
      deferred1_1 = ret[1];
      return getStringFromWasm0(ret[0], ret[1]);
    } finally {
      wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
  }
  /**
   * Get a Record containing the descriptions of all the linting rules, formatted as Markdown.
   * @returns {any}
   */
  get_lint_descriptions_as_object() {
    const ret = wasm.linter_get_lint_descriptions_as_object(this.__wbg_ptr);
    return ret;
  }
  /**
   * Get a JSON map containing the descriptions of all the linting rules, formatted as HTML.
   * @returns {string}
   */
  get_lint_descriptions_html_as_json() {
    let deferred1_0;
    let deferred1_1;
    try {
      const ret = wasm.linter_get_lint_descriptions_html_as_json(this.__wbg_ptr);
      deferred1_0 = ret[0];
      deferred1_1 = ret[1];
      return getStringFromWasm0(ret[0], ret[1]);
    } finally {
      wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
  }
  /**
   * Get a Record containing the descriptions of all the linting rules, formatted as HTML.
   * @returns {any}
   */
  get_lint_descriptions_html_as_object() {
    const ret = wasm.linter_get_lint_descriptions_html_as_object(this.__wbg_ptr);
    return ret;
  }
  /**
   * @returns {string}
   */
  get_structured_lint_config_as_json() {
    let deferred1_0;
    let deferred1_1;
    try {
      const ret = wasm.linter_get_structured_lint_config_as_json(this.__wbg_ptr);
      deferred1_0 = ret[0];
      deferred1_1 = ret[1];
      return getStringFromWasm0(ret[0], ret[1]);
    } finally {
      wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
  }
  /**
   * @returns {any}
   */
  get_structured_lint_config_as_object() {
    const ret = wasm.linter_get_structured_lint_config_as_object(this.__wbg_ptr);
    return ret;
  }
  /**
   * Add a specific context hash to the ignored lints list.
   * @param {BigUint64Array} hashes
   */
  ignore_hashes(hashes) {
    const ptr0 = passArray64ToWasm0(hashes, wasm.__wbindgen_malloc);
    const len0 = WASM_VECTOR_LEN;
    wasm.linter_ignore_hashes(this.__wbg_ptr, ptr0, len0);
  }
  /**
   * @param {string} source_text
   * @param {Lint[]} lints
   */
  ignore_lints(source_text, lints) {
    const ptr0 = passStringToWasm0(source_text, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    const ptr1 = passArrayJsValueToWasm0(lints, wasm.__wbindgen_malloc);
    const len1 = WASM_VECTOR_LEN;
    wasm.linter_ignore_lints(this.__wbg_ptr, ptr0, len0, ptr1, len1);
  }
  /**
   * Import into the linter's ignored lints from a privacy-respecting JSON list of hashes.
   * @param {string} json
   */
  import_ignored_lints(json) {
    const ptr0 = passStringToWasm0(json, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    const ret = wasm.linter_import_ignored_lints(this.__wbg_ptr, ptr0, len0);
    if (ret[1]) {
      throw takeFromExternrefTable0(ret[0]);
    }
  }
  /**
   * @param {string} file
   */
  import_stats_file(file) {
    const ptr0 = passStringToWasm0(file, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    const ret = wasm.linter_import_stats_file(this.__wbg_ptr, ptr0, len0);
    if (ret[1]) {
      throw takeFromExternrefTable0(ret[0]);
    }
  }
  /**
   * Load a Weirpack from raw bytes, merging its rules into the current linter.
   * Returns test failures if any are found, and does not import in that case.
   * @param {Uint8Array} bytes
   * @returns {any}
   */
  import_weirpack(bytes) {
    const ptr0 = passArray8ToWasm0(bytes, wasm.__wbindgen_malloc);
    const len0 = WASM_VECTOR_LEN;
    const ret = wasm.linter_import_weirpack(this.__wbg_ptr, ptr0, len0);
    if (ret[2]) {
      throw takeFromExternrefTable0(ret[1]);
    }
    return takeFromExternrefTable0(ret[0]);
  }
  /**
   * Import words into the dictionary.
   * @param {string[]} additional_words
   */
  import_words(additional_words) {
    const ptr0 = passArrayJsValueToWasm0(additional_words, wasm.__wbindgen_malloc);
    const len0 = WASM_VECTOR_LEN;
    wasm.linter_import_words(this.__wbg_ptr, ptr0, len0);
  }
  /**
   * Helper method to quickly check if a plain string is likely intended to be English
   * @param {string} text
   * @returns {boolean}
   */
  is_likely_english(text) {
    const ptr0 = passStringToWasm0(text, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    const ret = wasm.linter_is_likely_english(this.__wbg_ptr, ptr0, len0);
    return ret !== 0;
  }
  /**
   * Helper method to remove non-English text from a plain English document.
   * @param {string} text
   * @returns {string}
   */
  isolate_english(text) {
    let deferred2_0;
    let deferred2_1;
    try {
      const ptr0 = passStringToWasm0(text, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
      const len0 = WASM_VECTOR_LEN;
      const ret = wasm.linter_isolate_english(this.__wbg_ptr, ptr0, len0);
      deferred2_0 = ret[0];
      deferred2_1 = ret[1];
      return getStringFromWasm0(ret[0], ret[1]);
    } finally {
      wasm.__wbindgen_free(deferred2_0, deferred2_1, 1);
    }
  }
  /**
   * Perform the configured linting on the provided text.
   *
   * If the provided regex mask cannot be parsed, this method will return an empty array.
   * @param {string} text
   * @param {Language} language
   * @param {boolean} all_headings
   * @param {string | null | undefined} regex_mask
   * @param {boolean} dedup
   * @returns {Lint[]}
   */
  lint(text, language, all_headings, regex_mask, dedup) {
    const ptr0 = passStringToWasm0(text, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    var ptr1 = isLikeNone(regex_mask) ? 0 : passStringToWasm0(regex_mask, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    var len1 = WASM_VECTOR_LEN;
    const ret = wasm.linter_lint(this.__wbg_ptr, ptr0, len0, language, all_headings, ptr1, len1, dedup);
    var v3 = getArrayJsValueFromWasm0(ret[0], ret[1]).slice();
    wasm.__wbindgen_free(ret[0], ret[1] * 4, 4);
    return v3;
  }
  /**
   * Construct a new \`Linter\`.
   * Note that this can mean constructing the curated dictionary, which is the most expensive operation
   * in Harper.
   * @param {Dialect} dialect
   * @returns {Linter}
   */
  static new(dialect) {
    const ret = wasm.linter_new(dialect);
    return Linter2.__wrap(ret);
  }
  /**
   * @param {string} text
   * @param {Language} language
   * @param {boolean} all_headings
   * @param {string | null | undefined} regex_mask
   * @param {boolean} dedup
   * @returns {OrganizedGroup[]}
   */
  organized_lints(text, language, all_headings, regex_mask, dedup) {
    const ptr0 = passStringToWasm0(text, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    var ptr1 = isLikeNone(regex_mask) ? 0 : passStringToWasm0(regex_mask, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    var len1 = WASM_VECTOR_LEN;
    const ret = wasm.linter_organized_lints(this.__wbg_ptr, ptr0, len0, language, all_headings, ptr1, len1, dedup);
    var v3 = getArrayJsValueFromWasm0(ret[0], ret[1]).slice();
    wasm.__wbindgen_free(ret[0], ret[1] * 4, 4);
    return v3;
  }
  /**
   * @param {string} json
   */
  set_lint_config_from_json(json) {
    const ptr0 = passStringToWasm0(json, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    const ret = wasm.linter_set_lint_config_from_json(this.__wbg_ptr, ptr0, len0);
    if (ret[1]) {
      throw takeFromExternrefTable0(ret[0]);
    }
  }
  /**
   * @param {any} object
   */
  set_lint_config_from_object(object) {
    const ret = wasm.linter_set_lint_config_from_object(this.__wbg_ptr, object);
    if (ret[1]) {
      throw takeFromExternrefTable0(ret[0]);
    }
  }
  /**
   * @param {bigint | null} [start_time]
   * @param {bigint | null} [end_time]
   * @returns {any}
   */
  summarize_stats(start_time, end_time) {
    const ret = wasm.linter_summarize_stats(this.__wbg_ptr, !isLikeNone(start_time), isLikeNone(start_time) ? BigInt(0) : start_time, !isLikeNone(end_time), isLikeNone(end_time) ? BigInt(0) : end_time);
    return ret;
  }
}
if (Symbol.dispose) Linter2.prototype[Symbol.dispose] = Linter2.prototype.free;
class OrganizedGroup2 {
  static __wrap(ptr) {
    const obj = Object.create(OrganizedGroup2.prototype);
    obj.__wbg_ptr = ptr;
    OrganizedGroupFinalization.register(obj, obj.__wbg_ptr, obj);
    return obj;
  }
  __destroy_into_raw() {
    const ptr = this.__wbg_ptr;
    this.__wbg_ptr = 0;
    OrganizedGroupFinalization.unregister(this);
    return ptr;
  }
  free() {
    const ptr = this.__destroy_into_raw();
    wasm.__wbg_organizedgroup_free(ptr, 0);
  }
  /**
   * @returns {string}
   */
  get group() {
    let deferred1_0;
    let deferred1_1;
    try {
      const ret = wasm.__wbg_get_organizedgroup_group(this.__wbg_ptr);
      deferred1_0 = ret[0];
      deferred1_1 = ret[1];
      return getStringFromWasm0(ret[0], ret[1]);
    } finally {
      wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
  }
  /**
   * @returns {Lint[]}
   */
  get lints() {
    const ret = wasm.__wbg_get_organizedgroup_lints(this.__wbg_ptr);
    var v1 = getArrayJsValueFromWasm0(ret[0], ret[1]).slice();
    wasm.__wbindgen_free(ret[0], ret[1] * 4, 4);
    return v1;
  }
  /**
   * @param {string} arg0
   */
  set group(arg0) {
    const ptr0 = passStringToWasm0(arg0, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    wasm.__wbg_set_organizedgroup_group(this.__wbg_ptr, ptr0, len0);
  }
  /**
   * @param {Lint[]} arg0
   */
  set lints(arg0) {
    const ptr0 = passArrayJsValueToWasm0(arg0, wasm.__wbindgen_malloc);
    const len0 = WASM_VECTOR_LEN;
    wasm.__wbg_set_organizedgroup_lints(this.__wbg_ptr, ptr0, len0);
  }
}
if (Symbol.dispose) OrganizedGroup2.prototype[Symbol.dispose] = OrganizedGroup2.prototype.free;
class Span2 {
  static __wrap(ptr) {
    const obj = Object.create(Span2.prototype);
    obj.__wbg_ptr = ptr;
    SpanFinalization.register(obj, obj.__wbg_ptr, obj);
    return obj;
  }
  __destroy_into_raw() {
    const ptr = this.__wbg_ptr;
    this.__wbg_ptr = 0;
    SpanFinalization.unregister(this);
    return ptr;
  }
  free() {
    const ptr = this.__destroy_into_raw();
    wasm.__wbg_span_free(ptr, 0);
  }
  /**
   * @returns {number}
   */
  get end() {
    const ret = wasm.__wbg_get_span_end(this.__wbg_ptr);
    return ret >>> 0;
  }
  /**
   * @returns {number}
   */
  get start() {
    const ret = wasm.__wbg_get_span_start(this.__wbg_ptr);
    return ret >>> 0;
  }
  /**
   * @param {number} arg0
   */
  set end(arg0) {
    wasm.__wbg_set_span_end(this.__wbg_ptr, arg0);
  }
  /**
   * @param {number} arg0
   */
  set start(arg0) {
    wasm.__wbg_set_span_start(this.__wbg_ptr, arg0);
  }
  /**
   * @param {string} json
   * @returns {Span}
   */
  static from_json(json) {
    const ptr0 = passStringToWasm0(json, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    const ret = wasm.span_from_json(ptr0, len0);
    if (ret[2]) {
      throw takeFromExternrefTable0(ret[1]);
    }
    return Span2.__wrap(ret[0]);
  }
  /**
   * @returns {boolean}
   */
  is_empty() {
    const ret = wasm.span_is_empty(this.__wbg_ptr);
    return ret !== 0;
  }
  /**
   * @returns {number}
   */
  len() {
    const ret = wasm.span_len(this.__wbg_ptr);
    return ret >>> 0;
  }
  /**
   * @param {number} start
   * @param {number} end
   * @returns {Span}
   */
  static new(start, end) {
    const ret = wasm.span_new(start, end);
    return Span2.__wrap(ret);
  }
  /**
   * @returns {string}
   */
  to_json() {
    let deferred1_0;
    let deferred1_1;
    try {
      const ret = wasm.span_to_json(this.__wbg_ptr);
      deferred1_0 = ret[0];
      deferred1_1 = ret[1];
      return getStringFromWasm0(ret[0], ret[1]);
    } finally {
      wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
  }
}
if (Symbol.dispose) Span2.prototype[Symbol.dispose] = Span2.prototype.free;
class Suggestion2 {
  static __wrap(ptr) {
    const obj = Object.create(Suggestion2.prototype);
    obj.__wbg_ptr = ptr;
    SuggestionFinalization.register(obj, obj.__wbg_ptr, obj);
    return obj;
  }
  __destroy_into_raw() {
    const ptr = this.__wbg_ptr;
    this.__wbg_ptr = 0;
    SuggestionFinalization.unregister(this);
    return ptr;
  }
  free() {
    const ptr = this.__destroy_into_raw();
    wasm.__wbg_suggestion_free(ptr, 0);
  }
  /**
   * @param {string} json
   * @returns {Suggestion}
   */
  static from_json(json) {
    const ptr0 = passStringToWasm0(json, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    const ret = wasm.suggestion_from_json(ptr0, len0);
    if (ret[2]) {
      throw takeFromExternrefTable0(ret[1]);
    }
    return Suggestion2.__wrap(ret[0]);
  }
  /**
   * Get the text that is going to replace the problematic section.
   * If [\`Self::kind\`] is \`SuggestionKind::Remove\`, this will return an empty
   * string.
   * @returns {string}
   */
  get_replacement_text() {
    let deferred1_0;
    let deferred1_1;
    try {
      const ret = wasm.suggestion_get_replacement_text(this.__wbg_ptr);
      deferred1_0 = ret[0];
      deferred1_1 = ret[1];
      return getStringFromWasm0(ret[0], ret[1]);
    } finally {
      wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
  }
  /**
   * @returns {SuggestionKind}
   */
  kind() {
    const ret = wasm.suggestion_kind(this.__wbg_ptr);
    return ret;
  }
  /**
   * @returns {string}
   */
  to_json() {
    let deferred1_0;
    let deferred1_1;
    try {
      const ret = wasm.suggestion_to_json(this.__wbg_ptr);
      deferred1_0 = ret[0];
      deferred1_1 = ret[1];
      return getStringFromWasm0(ret[0], ret[1]);
    } finally {
      wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
    }
  }
}
if (Symbol.dispose) Suggestion2.prototype[Symbol.dispose] = Suggestion2.prototype.free;
const SuggestionKind = Object.freeze({
  /**
   * Replace the problematic text.
   */
  Replace: 0,
  "0": "Replace",
  /**
   * Remove the problematic text.
   */
  Remove: 1,
  "1": "Remove",
  /**
   * Insert additional text after the error.
   */
  InsertAfter: 2,
  "2": "InsertAfter"
});
function get_default_lint_config() {
  const ret = wasm.get_default_lint_config();
  return ret;
}
function get_default_lint_config_as_json() {
  let deferred1_0;
  let deferred1_1;
  try {
    const ret = wasm.get_default_lint_config_as_json();
    deferred1_0 = ret[0];
    deferred1_1 = ret[1];
    return getStringFromWasm0(ret[0], ret[1]);
  } finally {
    wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
  }
}
function setup() {
  wasm.setup();
}
function to_title_case(text) {
  let deferred2_0;
  let deferred2_1;
  try {
    const ptr0 = passStringToWasm0(text, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
    const len0 = WASM_VECTOR_LEN;
    const ret = wasm.to_title_case(ptr0, len0);
    deferred2_0 = ret[0];
    deferred2_1 = ret[1];
    return getStringFromWasm0(ret[0], ret[1]);
  } finally {
    wasm.__wbindgen_free(deferred2_0, deferred2_1, 1);
  }
}
function __wbg_get_imports() {
  const import0 = {
    __proto__: null,
    __wbg_Error_bce6d499ff0a4aff: function(arg0, arg1) {
      const ret = Error(getStringFromWasm0(arg0, arg1));
      return ret;
    },
    __wbg_String_8564e559799eccda: function(arg0, arg1) {
      const ret = String(arg1);
      const ptr1 = passStringToWasm0(ret, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
      const len1 = WASM_VECTOR_LEN;
      getDataViewMemory0().setInt32(arg0 + 4 * 1, len1, true);
      getDataViewMemory0().setInt32(arg0 + 4 * 0, ptr1, true);
    },
    __wbg___wbindgen_boolean_get_2304fb8c853028c8: function(arg0) {
      const v = arg0;
      const ret = typeof v === "boolean" ? v : void 0;
      return isLikeNone(ret) ? 16777215 : ret ? 1 : 0;
    },
    __wbg___wbindgen_debug_string_edece8177ad01481: function(arg0, arg1) {
      const ret = debugString(arg1);
      const ptr1 = passStringToWasm0(ret, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
      const len1 = WASM_VECTOR_LEN;
      getDataViewMemory0().setInt32(arg0 + 4 * 1, len1, true);
      getDataViewMemory0().setInt32(arg0 + 4 * 0, ptr1, true);
    },
    __wbg___wbindgen_is_function_5cd60d5cf78b4eef: function(arg0) {
      const ret = typeof arg0 === "function";
      return ret;
    },
    __wbg___wbindgen_is_object_b4593df85baada48: function(arg0) {
      const val = arg0;
      const ret = typeof val === "object" && val !== null;
      return ret;
    },
    __wbg___wbindgen_is_string_dde0fd9020db4434: function(arg0) {
      const ret = typeof arg0 === "string";
      return ret;
    },
    __wbg___wbindgen_jsval_loose_eq_0ad77b7717db155c: function(arg0, arg1) {
      const ret = arg0 == arg1;
      return ret;
    },
    __wbg___wbindgen_number_get_f73a1244370fcc2c: function(arg0, arg1) {
      const obj = arg1;
      const ret = typeof obj === "number" ? obj : void 0;
      getDataViewMemory0().setFloat64(arg0 + 8 * 1, isLikeNone(ret) ? 0 : ret, true);
      getDataViewMemory0().setInt32(arg0 + 4 * 0, !isLikeNone(ret), true);
    },
    __wbg___wbindgen_string_get_d109740c0d18f4d7: function(arg0, arg1) {
      const obj = arg1;
      const ret = typeof obj === "string" ? obj : void 0;
      var ptr1 = isLikeNone(ret) ? 0 : passStringToWasm0(ret, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
      var len1 = WASM_VECTOR_LEN;
      getDataViewMemory0().setInt32(arg0 + 4 * 1, len1, true);
      getDataViewMemory0().setInt32(arg0 + 4 * 0, ptr1, true);
    },
    __wbg___wbindgen_throw_9c31b086c2b26051: function(arg0, arg1) {
      throw new Error(getStringFromWasm0(arg0, arg1));
    },
    __wbg_call_13665d9f14390edc: function() {
      return handleError(function(arg0, arg1) {
        const ret = arg0.call(arg1);
        return ret;
      }, arguments);
    },
    __wbg_done_54b8da57023b7ed2: function(arg0) {
      const ret = arg0.done;
      return ret;
    },
    __wbg_entries_564a7e8b1e54ede5: function(arg0) {
      const ret = Object.entries(arg0);
      return ret;
    },
    __wbg_error_a6fa202b58aa1cd3: function(arg0, arg1) {
      let deferred0_0;
      let deferred0_1;
      try {
        deferred0_0 = arg0;
        deferred0_1 = arg1;
        console.error(getStringFromWasm0(arg0, arg1));
      } finally {
        wasm.__wbindgen_free(deferred0_0, deferred0_1, 1);
      }
    },
    __wbg_getRandomValues_3f44b700395062e5: function() {
      return handleError(function(arg0, arg1) {
        globalThis.crypto.getRandomValues(getArrayU8FromWasm0(arg0, arg1));
      }, arguments);
    },
    __wbg_getRandomValues_d49329ff89a07af1: function() {
      return handleError(function(arg0, arg1) {
        globalThis.crypto.getRandomValues(getArrayU8FromWasm0(arg0, arg1));
      }, arguments);
    },
    __wbg_getTime_09f1dd40a44edb30: function(arg0) {
      const ret = arg0.getTime();
      return ret;
    },
    __wbg_get_3e9a707ab7d352eb: function() {
      return handleError(function(arg0, arg1) {
        const ret = Reflect.get(arg0, arg1);
        return ret;
      }, arguments);
    },
    __wbg_get_98fdf51d029a75eb: function(arg0, arg1) {
      const ret = arg0[arg1 >>> 0];
      return ret;
    },
    __wbg_get_unchecked_1dfe6d05ad91d9b7: function(arg0, arg1) {
      const ret = arg0[arg1 >>> 0];
      return ret;
    },
    __wbg_instanceof_ArrayBuffer_53db37b06f6b9afe: function(arg0) {
      let result;
      try {
        result = arg0 instanceof ArrayBuffer;
      } catch (_) {
        result = false;
      }
      const ret = result;
      return ret;
    },
    __wbg_instanceof_Uint8Array_abd07d4bd221d50b: function(arg0) {
      let result;
      try {
        result = arg0 instanceof Uint8Array;
      } catch (_) {
        result = false;
      }
      const ret = result;
      return ret;
    },
    __wbg_iterator_1441b47f341dc34f: function() {
      const ret = Symbol.iterator;
      return ret;
    },
    __wbg_length_2591a0f4f659a55c: function(arg0) {
      const ret = arg0.length;
      return ret;
    },
    __wbg_length_56fcd3e2b7e0299d: function(arg0) {
      const ret = arg0.length;
      return ret;
    },
    __wbg_lint_new: function(arg0) {
      const ret = Lint2.__wrap(arg0);
      return ret;
    },
    __wbg_lint_unwrap: function(arg0) {
      const ret = Lint2.__unwrap(arg0);
      return ret;
    },
    __wbg_log_0c201ade58bb55e1: function(arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7) {
      let deferred0_0;
      let deferred0_1;
      try {
        deferred0_0 = arg0;
        deferred0_1 = arg1;
        console.log(getStringFromWasm0(arg0, arg1), getStringFromWasm0(arg2, arg3), getStringFromWasm0(arg4, arg5), getStringFromWasm0(arg6, arg7));
      } finally {
        wasm.__wbindgen_free(deferred0_0, deferred0_1, 1);
      }
    },
    __wbg_log_ce2c4456b290c5e7: function(arg0, arg1) {
      let deferred0_0;
      let deferred0_1;
      try {
        deferred0_0 = arg0;
        deferred0_1 = arg1;
        console.log(getStringFromWasm0(arg0, arg1));
      } finally {
        wasm.__wbindgen_free(deferred0_0, deferred0_1, 1);
      }
    },
    __wbg_mark_b4d943f3bc2d2404: function(arg0, arg1) {
      performance.mark(getStringFromWasm0(arg0, arg1));
    },
    __wbg_measure_84362959e621a2c1: function() {
      return handleError(function(arg0, arg1, arg2, arg3) {
        let deferred0_0;
        let deferred0_1;
        let deferred1_0;
        let deferred1_1;
        try {
          deferred0_0 = arg0;
          deferred0_1 = arg1;
          deferred1_0 = arg2;
          deferred1_1 = arg3;
          performance.measure(getStringFromWasm0(arg0, arg1), getStringFromWasm0(arg2, arg3));
        } finally {
          wasm.__wbindgen_free(deferred0_0, deferred0_1, 1);
          wasm.__wbindgen_free(deferred1_0, deferred1_1, 1);
        }
      }, arguments);
    },
    __wbg_new_02d162bc6cf02f60: function() {
      const ret = new Object();
      return ret;
    },
    __wbg_new_070df68d66325372: function() {
      const ret = /* @__PURE__ */ new Map();
      return ret;
    },
    __wbg_new_0_2722fcdb71a888a6: function() {
      const ret = /* @__PURE__ */ new Date();
      return ret;
    },
    __wbg_new_227d7c05414eb861: function() {
      const ret = new Error();
      return ret;
    },
    __wbg_new_310879b66b6e95e1: function() {
      const ret = new Array();
      return ret;
    },
    __wbg_new_7ddec6de44ff8f5d: function(arg0) {
      const ret = new Uint8Array(arg0);
      return ret;
    },
    __wbg_next_2a4e19f4f5083b0f: function(arg0) {
      const ret = arg0.next;
      return ret;
    },
    __wbg_next_6429a146bf756f93: function() {
      return handleError(function(arg0) {
        const ret = arg0.next();
        return ret;
      }, arguments);
    },
    __wbg_organizedgroup_new: function(arg0) {
      const ret = OrganizedGroup2.__wrap(arg0);
      return ret;
    },
    __wbg_prototypesetcall_5f9bdc8d75e07276: function(arg0, arg1, arg2) {
      Uint8Array.prototype.set.call(getArrayU8FromWasm0(arg0, arg1), arg2);
    },
    __wbg_set_6be42768c690e380: function(arg0, arg1, arg2) {
      arg0[arg1] = arg2;
    },
    __wbg_set_78ea6a19f4818587: function(arg0, arg1, arg2) {
      arg0[arg1 >>> 0] = arg2;
    },
    __wbg_set_facb7a5914e0fa39: function(arg0, arg1, arg2) {
      const ret = arg0.set(arg1, arg2);
      return ret;
    },
    __wbg_stack_3b0d974bbf31e44f: function(arg0, arg1) {
      const ret = arg1.stack;
      const ptr1 = passStringToWasm0(ret, wasm.__wbindgen_malloc, wasm.__wbindgen_realloc);
      const len1 = WASM_VECTOR_LEN;
      getDataViewMemory0().setInt32(arg0 + 4 * 1, len1, true);
      getDataViewMemory0().setInt32(arg0 + 4 * 0, ptr1, true);
    },
    __wbg_suggestion_new: function(arg0) {
      const ret = Suggestion2.__wrap(arg0);
      return ret;
    },
    __wbg_value_9cc0518af87a489c: function(arg0) {
      const ret = arg0.value;
      return ret;
    },
    __wbindgen_cast_0000000000000001: function(arg0) {
      const ret = arg0;
      return ret;
    },
    __wbindgen_cast_0000000000000002: function(arg0, arg1) {
      const ret = getStringFromWasm0(arg0, arg1);
      return ret;
    },
    __wbindgen_init_externref_table: function() {
      const table = wasm.__wbindgen_externrefs;
      const offset = table.grow(4);
      table.set(0, void 0);
      table.set(offset + 0, void 0);
      table.set(offset + 1, null);
      table.set(offset + 2, true);
      table.set(offset + 3, false);
    }
  };
  return {
    __proto__: null,
    "./harper_wasm_bg.js": import0
  };
}
const LintFinalization = typeof FinalizationRegistry === "undefined" ? { register: () => {
}, unregister: () => {
} } : new FinalizationRegistry((ptr) => wasm.__wbg_lint_free(ptr, 1));
const LinterFinalization = typeof FinalizationRegistry === "undefined" ? { register: () => {
}, unregister: () => {
} } : new FinalizationRegistry((ptr) => wasm.__wbg_linter_free(ptr, 1));
const OrganizedGroupFinalization = typeof FinalizationRegistry === "undefined" ? { register: () => {
}, unregister: () => {
} } : new FinalizationRegistry((ptr) => wasm.__wbg_organizedgroup_free(ptr, 1));
const SpanFinalization = typeof FinalizationRegistry === "undefined" ? { register: () => {
}, unregister: () => {
} } : new FinalizationRegistry((ptr) => wasm.__wbg_span_free(ptr, 1));
const SuggestionFinalization = typeof FinalizationRegistry === "undefined" ? { register: () => {
}, unregister: () => {
} } : new FinalizationRegistry((ptr) => wasm.__wbg_suggestion_free(ptr, 1));
function addToExternrefTable0(obj) {
  const idx = wasm.__externref_table_alloc();
  wasm.__wbindgen_externrefs.set(idx, obj);
  return idx;
}
function _assertClass(instance, klass) {
  if (!(instance instanceof klass)) {
    throw new Error(\`expected instance of \${klass.name}\`);
  }
}
function debugString(val) {
  const type = typeof val;
  if (type == "number" || type == "boolean" || val == null) {
    return \`\${val}\`;
  }
  if (type == "string") {
    return \`"\${val}"\`;
  }
  if (type == "symbol") {
    const description = val.description;
    if (description == null) {
      return "Symbol";
    } else {
      return \`Symbol(\${description})\`;
    }
  }
  if (type == "function") {
    const name = val.name;
    if (typeof name == "string" && name.length > 0) {
      return \`Function(\${name})\`;
    } else {
      return "Function";
    }
  }
  if (Array.isArray(val)) {
    const length = val.length;
    let debug = "[";
    if (length > 0) {
      debug += debugString(val[0]);
    }
    for (let i = 1; i < length; i++) {
      debug += ", " + debugString(val[i]);
    }
    debug += "]";
    return debug;
  }
  const builtInMatches = /\\[object ([^\\]]+)\\]/.exec(toString.call(val));
  let className;
  if (builtInMatches && builtInMatches.length > 1) {
    className = builtInMatches[1];
  } else {
    return toString.call(val);
  }
  if (className == "Object") {
    try {
      return "Object(" + JSON.stringify(val) + ")";
    } catch (_) {
      return "Object";
    }
  }
  if (val instanceof Error) {
    return \`\${val.name}: \${val.message}
\${val.stack}\`;
  }
  return className;
}
function getArrayJsValueFromWasm0(ptr, len) {
  ptr = ptr >>> 0;
  const mem = getDataViewMemory0();
  const result = [];
  for (let i = ptr; i < ptr + 4 * len; i += 4) {
    result.push(wasm.__wbindgen_externrefs.get(mem.getUint32(i, true)));
  }
  wasm.__externref_drop_slice(ptr, len);
  return result;
}
function getArrayU8FromWasm0(ptr, len) {
  ptr = ptr >>> 0;
  return getUint8ArrayMemory0().subarray(ptr / 1, ptr / 1 + len);
}
let cachedBigUint64ArrayMemory0 = null;
function getBigUint64ArrayMemory0() {
  if (cachedBigUint64ArrayMemory0 === null || cachedBigUint64ArrayMemory0.byteLength === 0) {
    cachedBigUint64ArrayMemory0 = new BigUint64Array(wasm.memory.buffer);
  }
  return cachedBigUint64ArrayMemory0;
}
let cachedDataViewMemory0 = null;
function getDataViewMemory0() {
  if (cachedDataViewMemory0 === null || cachedDataViewMemory0.buffer.detached === true || cachedDataViewMemory0.buffer.detached === void 0 && cachedDataViewMemory0.buffer !== wasm.memory.buffer) {
    cachedDataViewMemory0 = new DataView(wasm.memory.buffer);
  }
  return cachedDataViewMemory0;
}
function getStringFromWasm0(ptr, len) {
  return decodeText(ptr >>> 0, len);
}
let cachedUint8ArrayMemory0 = null;
function getUint8ArrayMemory0() {
  if (cachedUint8ArrayMemory0 === null || cachedUint8ArrayMemory0.byteLength === 0) {
    cachedUint8ArrayMemory0 = new Uint8Array(wasm.memory.buffer);
  }
  return cachedUint8ArrayMemory0;
}
function handleError(f, args) {
  try {
    return f.apply(this, args);
  } catch (e) {
    const idx = addToExternrefTable0(e);
    wasm.__wbindgen_exn_store(idx);
  }
}
function isLikeNone(x) {
  return x === void 0 || x === null;
}
function passArray64ToWasm0(arg, malloc) {
  const ptr = malloc(arg.length * 8, 8) >>> 0;
  getBigUint64ArrayMemory0().set(arg, ptr / 8);
  WASM_VECTOR_LEN = arg.length;
  return ptr;
}
function passArray8ToWasm0(arg, malloc) {
  const ptr = malloc(arg.length * 1, 1) >>> 0;
  getUint8ArrayMemory0().set(arg, ptr / 1);
  WASM_VECTOR_LEN = arg.length;
  return ptr;
}
function passArrayJsValueToWasm0(array, malloc) {
  const ptr = malloc(array.length * 4, 4) >>> 0;
  for (let i = 0; i < array.length; i++) {
    const add = addToExternrefTable0(array[i]);
    getDataViewMemory0().setUint32(ptr + 4 * i, add, true);
  }
  WASM_VECTOR_LEN = array.length;
  return ptr;
}
function passStringToWasm0(arg, malloc, realloc) {
  if (realloc === void 0) {
    const buf = cachedTextEncoder.encode(arg);
    const ptr2 = malloc(buf.length, 1) >>> 0;
    getUint8ArrayMemory0().subarray(ptr2, ptr2 + buf.length).set(buf);
    WASM_VECTOR_LEN = buf.length;
    return ptr2;
  }
  let len = arg.length;
  let ptr = malloc(len, 1) >>> 0;
  const mem = getUint8ArrayMemory0();
  let offset = 0;
  for (; offset < len; offset++) {
    const code = arg.charCodeAt(offset);
    if (code > 127) break;
    mem[ptr + offset] = code;
  }
  if (offset !== len) {
    if (offset !== 0) {
      arg = arg.slice(offset);
    }
    ptr = realloc(ptr, len, len = offset + arg.length * 3, 1) >>> 0;
    const view = getUint8ArrayMemory0().subarray(ptr + offset, ptr + len);
    const ret = cachedTextEncoder.encodeInto(arg, view);
    offset += ret.written;
    ptr = realloc(ptr, len, offset, 1) >>> 0;
  }
  WASM_VECTOR_LEN = offset;
  return ptr;
}
function takeFromExternrefTable0(idx) {
  const value = wasm.__wbindgen_externrefs.get(idx);
  wasm.__externref_table_dealloc(idx);
  return value;
}
let cachedTextDecoder = new TextDecoder("utf-8", { ignoreBOM: true, fatal: true });
cachedTextDecoder.decode();
const MAX_SAFARI_DECODE_BYTES = 2146435072;
let numBytesDecoded = 0;
function decodeText(ptr, len) {
  numBytesDecoded += len;
  if (numBytesDecoded >= MAX_SAFARI_DECODE_BYTES) {
    cachedTextDecoder = new TextDecoder("utf-8", { ignoreBOM: true, fatal: true });
    cachedTextDecoder.decode();
    numBytesDecoded = len;
  }
  return cachedTextDecoder.decode(getUint8ArrayMemory0().subarray(ptr, ptr + len));
}
const cachedTextEncoder = new TextEncoder();
if (!("encodeInto" in cachedTextEncoder)) {
  cachedTextEncoder.encodeInto = function(arg, view) {
    const buf = cachedTextEncoder.encode(arg);
    view.set(buf);
    return {
      read: arg.length,
      written: buf.length
    };
  };
}
let WASM_VECTOR_LEN = 0;
let wasm;
function __wbg_finalize_init(instance, module) {
  wasm = instance.exports;
  cachedBigUint64ArrayMemory0 = null;
  cachedDataViewMemory0 = null;
  cachedUint8ArrayMemory0 = null;
  wasm.__wbindgen_start();
  return wasm;
}
async function __wbg_load(module, imports) {
  if (typeof Response === "function" && module instanceof Response) {
    if (typeof WebAssembly.instantiateStreaming === "function") {
      try {
        return await WebAssembly.instantiateStreaming(module, imports);
      } catch (e) {
        const validResponse = module.ok && expectedResponseType(module.type);
        if (validResponse && module.headers.get("Content-Type") !== "application/wasm") {
          console.warn("\`WebAssembly.instantiateStreaming\` failed because your server does not serve Wasm with \`application/wasm\` MIME type. Falling back to \`WebAssembly.instantiate\` which is slower. Original error:\\n", e);
        } else {
          throw e;
        }
      }
    }
    const bytes = await module.arrayBuffer();
    return await WebAssembly.instantiate(bytes, imports);
  } else {
    const instance = await WebAssembly.instantiate(module, imports);
    if (instance instanceof WebAssembly.Instance) {
      return { instance, module };
    } else {
      return instance;
    }
  }
  function expectedResponseType(type) {
    switch (type) {
      case "basic":
      case "cors":
      case "default":
        return true;
    }
    return false;
  }
}
function initSync(module) {
  if (wasm !== void 0) return wasm;
  if (module !== void 0) {
    if (Object.getPrototypeOf(module) === Object.prototype) {
      ({ module } = module);
    } else {
      console.warn("using deprecated parameters for \`initSync()\`; pass a single object instead");
    }
  }
  const imports = __wbg_get_imports();
  if (!(module instanceof WebAssembly.Module)) {
    module = new WebAssembly.Module(module);
  }
  const instance = new WebAssembly.Instance(module, imports);
  return __wbg_finalize_init(instance);
}
async function __wbg_init(module_or_path) {
  if (wasm !== void 0) return wasm;
  if (module_or_path !== void 0) {
    if (Object.getPrototypeOf(module_or_path) === Object.prototype) {
      ({ module_or_path } = module_or_path);
    } else {
      console.warn("using deprecated parameters for the initialization function; pass a single object instead");
    }
  }
  if (module_or_path === void 0) {
    module_or_path = new URL();
  }
  const imports = __wbg_get_imports();
  if (typeof module_or_path === "string" || typeof Request === "function" && module_or_path instanceof Request || typeof URL === "function" && module_or_path instanceof URL) {
    module_or_path = fetch(module_or_path);
  }
  const { instance, module } = await __wbg_load(await module_or_path, imports);
  return __wbg_finalize_init(instance);
}
var fullGlue = /* @__PURE__ */ Object.freeze({
  __proto__: null,
  Dialect,
  Language,
  Lint: Lint2,
  Linter: Linter2,
  OrganizedGroup: OrganizedGroup2,
  Span: Span2,
  Suggestion: Suggestion2,
  SuggestionKind,
  default: __wbg_init,
  get_default_lint_config,
  get_default_lint_config_as_json,
  initSync,
  setup,
  to_title_case
});
const _PLazy = class _PLazy extends Promise {
  constructor(executor) {
    super((resolve) => {
      resolve();
    });
    __privateAdd(this, _executor);
    __privateAdd(this, _promise);
    __privateSet(this, _executor, executor);
  }
  static from(function_) {
    return new _PLazy((resolve) => {
      resolve(function_());
    });
  }
  static resolve(value) {
    return new _PLazy((resolve) => {
      resolve(value);
    });
  }
  static reject(error) {
    return new _PLazy((resolve, reject) => {
      reject(error);
    });
  }
  then(onFulfilled, onRejected) {
    __privateGet(this, _promise) ?? __privateSet(this, _promise, new Promise(__privateGet(this, _executor)));
    return __privateGet(this, _promise).then(onFulfilled, onRejected);
  }
  catch(onRejected) {
    __privateGet(this, _promise) ?? __privateSet(this, _promise, new Promise(__privateGet(this, _executor)));
    return __privateGet(this, _promise).catch(onRejected);
  }
  finally(onFinally) {
    __privateGet(this, _promise) ?? __privateSet(this, _promise, new Promise(__privateGet(this, _executor)));
    return __privateGet(this, _promise).finally(onFinally);
  }
};
_executor = new WeakMap();
_promise = new WeakMap();
let PLazy = _PLazy;
const copyProperty = (to, from, property, ignoreNonConfigurable) => {
  if (property === "length" || property === "prototype") {
    return;
  }
  if (property === "arguments" || property === "caller") {
    return;
  }
  const toDescriptor = Object.getOwnPropertyDescriptor(to, property);
  const fromDescriptor = Object.getOwnPropertyDescriptor(from, property);
  if (!canCopyProperty(toDescriptor, fromDescriptor) && ignoreNonConfigurable) {
    return;
  }
  Object.defineProperty(to, property, fromDescriptor);
};
const canCopyProperty = function(toDescriptor, fromDescriptor) {
  return toDescriptor === void 0 || toDescriptor.configurable || toDescriptor.writable === fromDescriptor.writable && toDescriptor.enumerable === fromDescriptor.enumerable && toDescriptor.configurable === fromDescriptor.configurable && (toDescriptor.writable || toDescriptor.value === fromDescriptor.value);
};
const changePrototype = (to, from) => {
  const fromPrototype = Object.getPrototypeOf(from);
  if (fromPrototype === Object.getPrototypeOf(to)) {
    return;
  }
  Object.setPrototypeOf(to, fromPrototype);
};
const wrappedToString = (withName, fromBody) => \`/* Wrapped \${withName}*/
\${fromBody}\`;
const toStringDescriptor = Object.getOwnPropertyDescriptor(Function.prototype, "toString");
const toStringName = Object.getOwnPropertyDescriptor(Function.prototype.toString, "name");
const changeToString = (to, from, name) => {
  const withName = name === "" ? "" : \`with \${name.trim()}() \`;
  const newToString = wrappedToString.bind(null, withName, from.toString());
  Object.defineProperty(newToString, "name", toStringName);
  Object.defineProperty(to, "toString", { ...toStringDescriptor, value: newToString });
};
function mimicFunction(to, from, { ignoreNonConfigurable = false } = {}) {
  const { name } = to;
  for (const property of Reflect.ownKeys(from)) {
    copyProperty(to, from, property, ignoreNonConfigurable);
  }
  changePrototype(to, from);
  changeToString(to, from, name);
  return to;
}
const cacheStore = /* @__PURE__ */ new WeakMap();
function pMemoize(fn, { cacheKey = ([firstArgument]) => firstArgument, cache = /* @__PURE__ */ new Map() } = {}) {
  const promiseCache = /* @__PURE__ */ new Map();
  const memoized = function(...arguments_) {
    const key = cacheKey(arguments_);
    if (promiseCache.has(key)) {
      return promiseCache.get(key);
    }
    const promise = (async () => {
      try {
        if (cache && await cache.has(key)) {
          return await cache.get(key);
        }
        const promise2 = fn.apply(this, arguments_);
        const result = await promise2;
        try {
          return result;
        } finally {
          if (cache) {
            await cache.set(key, result);
          }
        }
      } finally {
        promiseCache.delete(key);
      }
    })();
    promiseCache.set(key, promise);
    return promise;
  };
  mimicFunction(memoized, fn, {
    ignoreNonConfigurable: true
  });
  cacheStore.set(memoized, cache);
  return memoized;
}
function inferGlueFlavor(binary) {
  return binary.includes("harper_wasm_slim") ? "slim" : "full";
}
function loadGlue(glueFlavor) {
  if (glueFlavor === "slim") {
    return defaultGlue;
  }
  return fullGlue;
}
function getDefaultGlueBinary(binary, glueFlavor) {
  if (glueFlavor === "slim") {
    return binary;
  }
  if (binary.includes("harper_wasm_bg.wasm")) {
    return binary.replace("harper_wasm_bg.wasm", "harper_wasm_slim_bg.wasm");
  }
  return null;
}
function getInitInput(binary) {
  if (typeof process !== "undefined" && binary.startsWith("file://")) {
    return Promise.resolve().then(function() {
      return __viteBrowserExternal$1;
    }).then(
      (fs) => new Promise((resolve, reject) => {
        fs.readFile(new URL(binary).pathname, (err, data) => {
          if (err) reject(err);
          resolve(data);
        });
      })
    );
  }
  return binary;
}
async function loadBinaryUncached(binary, glueFlavor) {
  const exports = loadGlue(glueFlavor);
  const defaultGlueBinary = getDefaultGlueBinary(binary, glueFlavor);
  if (defaultGlueBinary != null) {
    try {
      await __wbg_init$1({ module_or_path: getInitInput(defaultGlueBinary) });
    } catch (err) {
      if (glueFlavor === "slim") {
        throw err;
      }
    }
  }
  await exports.default({ module_or_path: getInitInput(binary) });
  return exports;
}
const loadBinaryByFlavor = {
  full: pMemoize((binary) => loadBinaryUncached(binary, "full")),
  slim: pMemoize((binary) => loadBinaryUncached(binary, "slim"))
};
function loadBinary(binary, glueFlavor) {
  return loadBinaryByFlavor[glueFlavor](binary);
}
class BinaryModuleImpl {
  constructor() {
    __publicField(this, "url", "");
    __publicField(this, "glueFlavor", "full");
    __publicField(this, "inner", null);
  }
  /** Load a binary from a specified URL. This is the only recommended way to construct this type. */
  static create(url, glueFlavor) {
    const module = new SuperBinaryModule();
    module.url = url;
    module.glueFlavor = glueFlavor ?? inferGlueFlavor(typeof url === "string" ? url : url.href);
    module.inner = PLazy.from(
      () => loadBinary(typeof module.url === "string" ? module.url : module.url.href, module.glueFlavor)
    );
    return module;
  }
  async getDefaultLintConfigAsJSON() {
    const exported = await this.inner;
    return exported.get_default_lint_config_as_json();
  }
  async getDefaultLintConfig() {
    const exported = await this.inner;
    return exported.get_default_lint_config();
  }
  async toTitleCase(text) {
    const exported = await this.inner;
    return exported.to_title_case(text);
  }
  async setup() {
    const exported = await this.inner;
    exported.setup();
  }
}
class SuperBinaryModule extends BinaryModuleImpl {
  async createLinter(dialect) {
    const exported = await this.getBinaryModule();
    return exported.Linter.new(dialect ?? Dialect$1.American);
  }
  async getBinaryModule() {
    return await PLazy.from(
      () => loadBinary(typeof this.url === "string" ? this.url : this.url.href, this.glueFlavor)
    );
  }
}
class LocalLinter {
  constructor(init) {
    __publicField(this, "binary");
    __publicField(this, "inner");
    __publicField(this, "disposed", false);
    this.binary = init.binary;
    this.binary.setup();
    this.inner = this.createInner(init.dialect);
  }
  createInner(dialect) {
    return PLazy.from(async () => {
      await this.binary.setup();
      return this.binary.createLinter(dialect);
    });
  }
  async setup() {
    await this.lint("", { language: "plaintext" });
    const exported = await this.exportIgnoredLints();
    await this.importIgnoredLints(exported);
  }
  async lint(text, options) {
    const inner = await this.inner;
    let language = Language$1.Markdown;
    switch (options == null ? void 0 : options.language) {
      case "plaintext":
        language = Language$1.Plain;
        break;
      case "markdown":
        language = Language$1.Markdown;
        break;
      case "typst":
        language = Language$1.Typst;
    }
    const lints = inner.lint(
      text,
      language,
      (options == null ? void 0 : options.forceAllHeadings) ?? false,
      options == null ? void 0 : options.regex_mask,
      (options == null ? void 0 : options.dedup) ?? true
    );
    return lints;
  }
  async organizedLints(text, options) {
    const inner = await this.inner;
    let language = Language$1.Markdown;
    switch (options == null ? void 0 : options.language) {
      case "plaintext":
        language = Language$1.Plain;
        break;
      case "markdown":
        language = Language$1.Markdown;
        break;
      case "typst":
        language = Language$1.Typst;
        break;
    }
    const lintGroups = inner.organized_lints(
      text,
      language,
      (options == null ? void 0 : options.forceAllHeadings) ?? false,
      options == null ? void 0 : options.regex_mask,
      (options == null ? void 0 : options.dedup) ?? true
    );
    const output = {};
    for (const group of lintGroups) {
      output[group.group] = group.lints;
      group.free();
    }
    return output;
  }
  async applySuggestion(text, lint, suggestion) {
    const inner = await this.inner;
    return inner.apply_suggestion(text, lint, suggestion);
  }
  async isLikelyEnglish(text) {
    const inner = await this.inner;
    return inner.is_likely_english(text);
  }
  async isolateEnglish(text) {
    const inner = await this.inner;
    return inner.isolate_english(text);
  }
  async getLintConfig() {
    const inner = await this.inner;
    return inner.get_lint_config_as_object();
  }
  async getDefaultLintConfigAsJSON() {
    return await this.binary.getDefaultLintConfigAsJSON();
  }
  async getDefaultLintConfig() {
    return await this.binary.getDefaultLintConfig();
  }
  async getStructuredLintConfig() {
    const inner = await this.inner;
    return inner.get_structured_lint_config_as_object();
  }
  async getStructuredLintConfigJSON() {
    const inner = await this.inner;
    return inner.get_structured_lint_config_as_json();
  }
  async setLintConfig(config) {
    const inner = await this.inner;
    inner.set_lint_config_from_object(config);
  }
  async getLintConfigAsJSON() {
    const inner = await this.inner;
    return inner.get_lint_config_as_json();
  }
  async setLintConfigWithJSON(config) {
    const inner = await this.inner;
    inner.set_lint_config_from_json(config);
  }
  async toTitleCase(text) {
    return await this.binary.toTitleCase(text);
  }
  async getLintDescriptions() {
    const inner = await this.inner;
    return inner.get_lint_descriptions_as_object();
  }
  async getLintDescriptionsAsJSON() {
    const inner = await this.inner;
    return inner.get_lint_descriptions_as_json();
  }
  async getLintDescriptionsHTML() {
    const inner = await this.inner;
    return inner.get_lint_descriptions_html_as_object();
  }
  async getLintDescriptionsHTMLAsJSON() {
    const inner = await this.inner;
    return inner.get_lint_descriptions_html_as_json();
  }
  async ignoreLint(source, lint) {
    return await this.ignoreLints(source, [lint]);
  }
  async ignoreLints(source, lints) {
    const inner = await this.inner;
    inner.ignore_lints(source, lints);
  }
  async ignoreLintHash(hash) {
    const inner = await this.inner;
    inner.ignore_hashes(new BigUint64Array([hash]));
  }
  async exportIgnoredLints() {
    const inner = await this.inner;
    return inner.export_ignored_lints();
  }
  async importIgnoredLints(json) {
    const inner = await this.inner;
    inner.import_ignored_lints(json);
  }
  async contextHash(source, lint) {
    const inner = await this.inner;
    return inner.context_hash(source, lint);
  }
  async clearIgnoredLints() {
    const inner = await this.inner;
    inner.clear_ignored_lints();
  }
  async clearWords() {
    const inner = await this.inner;
    return inner.clear_words();
  }
  async importWords(words) {
    const inner = await this.inner;
    return inner.import_words(words);
  }
  async exportWords() {
    const inner = await this.inner;
    return inner.export_words();
  }
  async getDialect() {
    const inner = await this.inner;
    return inner.get_dialect();
  }
  async setDialect(dialect) {
    const inner = await this.inner;
    if (inner.get_dialect() !== dialect) {
      inner.free();
      this.inner = this.createInner(dialect);
    }
    return Promise.resolve();
  }
  async summarizeStats(start, end) {
    const inner = await this.inner;
    return inner.summarize_stats(start, end);
  }
  async generateStatsFile() {
    const inner = await this.inner;
    return inner.generate_stats_file();
  }
  async importStatsFile(statsFile) {
    const inner = await this.inner;
    return inner.import_stats_file(statsFile);
  }
  /**
   * Load a Weirpack from a Blob.
   *
   * Returns \`undefined\` if tests pass and rules are imported, otherwise returns
   * the Weirpack test failures.
   */
  async loadWeirpackFromBlob(blob) {
    const bytes = new Uint8Array(await blob.arrayBuffer());
    return this.loadWeirpackFromBytes(bytes);
  }
  /**
   * Load a Weirpack from a byte array.
   *
   * Returns \`undefined\` if tests pass and rules are imported, otherwise returns
   * the Weirpack test failures.
   */
  async loadWeirpackFromBytes(bytes) {
    const inner = await this.inner;
    const data = bytes instanceof Uint8Array ? bytes : Uint8Array.from(bytes);
    const result = inner.import_weirpack(data);
    return result;
  }
  async dispose() {
    if (this.disposed) {
      return;
    }
    this.disposed = true;
    const inner = await this.inner;
    inner.free();
  }
}
function assert(condition, message) {
  if (!condition) {
    throw new Error("Assertion failed");
  }
}
function isSerializedRequest(v) {
  return typeof v === "object" && v !== null && "procName" in v && "args" in v;
}
class Serializer {
  constructor(binary) {
    __publicField(this, "binary");
    this.binary = binary;
    this.binary.setup();
  }
  async serializeArg(arg) {
    var _a;
    const { Lint: Lint3, Span: Span3, Suggestion: Suggestion3 } = await this.binary.getBinaryModule();
    if (Array.isArray(arg)) {
      return {
        json: JSON.stringify(await Promise.all(arg.map((a) => this.serializeArg(a)))),
        type: "Array"
      };
    }
    const argType = typeof arg;
    switch (argType) {
      case "string":
      case "number":
      case "boolean":
      case "undefined":
        return { json: JSON.stringify(arg), type: argType };
      case "bigint":
        return { json: arg.toString(), type: argType };
    }
    if (arg.to_json !== void 0) {
      const json = arg.to_json();
      let type;
      const constructorName = (_a = arg.constructor) == null ? void 0 : _a.name;
      if (arg instanceof Lint3 || constructorName === "Lint") {
        type = "Lint";
      } else if (arg instanceof Suggestion3 || constructorName === "Suggestion") {
        type = "Suggestion";
      } else if (arg instanceof Span3 || constructorName === "Span") {
        type = "Span";
      }
      if (type === void 0) {
        throw new Error("Unhandled case: type undefined");
      }
      return { json, type };
    }
    if (argType == "object") {
      return {
        json: JSON.stringify(
          await Promise.all(
            Object.entries(arg).map(([key, value]) => this.serializeArg([key, value]))
          )
        ),
        type: "object"
      };
    }
    throw new Error(\`Unhandled case: \${arg}\`);
  }
  async serialize(req) {
    return {
      procName: req.procName,
      args: await Promise.all(req.args.map((arg) => this.serializeArg(arg)))
    };
  }
  async deserializeArg(requestArg) {
    const { Lint: Lint3, Span: Span3, Suggestion: Suggestion3 } = await this.binary.getBinaryModule();
    switch (requestArg.type) {
      case "bigint":
        return BigInt(requestArg.json);
      case "undefined":
        return void 0;
      case "boolean":
      case "number":
      case "string":
        return JSON.parse(requestArg.json);
      case "Suggestion":
        return Suggestion3.from_json(requestArg.json);
      case "Lint":
        return Lint3.from_json(requestArg.json);
      case "Span":
        return Span3.from_json(requestArg.json);
      case "Array": {
        const parsed = JSON.parse(requestArg.json);
        assert(Array.isArray(parsed));
        return await Promise.all(parsed.map((arg) => this.deserializeArg(arg)));
      }
      case "object": {
        const parsed = JSON.parse(requestArg.json);
        return Object.fromEntries(
          await Promise.all(parsed.map((val) => this.deserializeArg(val)))
        );
      }
      default:
        throw new Error(\`Unhandled case: \${requestArg.type}\`);
    }
  }
  async deserialize(request) {
    return {
      procName: request.procName,
      args: await Promise.all(request.args.map((arg) => this.deserializeArg(arg)))
    };
  }
}
self.postMessage("ready");
self.onmessage = (e) => {
  const [binaryUrl, dialect, glueFlavor] = e.data;
  if (typeof binaryUrl !== "string") {
    throw new TypeError(\`Expected binary to be a string of url but got \${typeof binaryUrl}.\`);
  }
  if (glueFlavor !== void 0 && glueFlavor !== "full" && glueFlavor !== "slim") {
    throw new TypeError(\`Expected glue flavor to be "full" or "slim" but got \${glueFlavor}.\`);
  }
  const binary = SuperBinaryModule.create(binaryUrl, glueFlavor);
  const serializer = new Serializer(binary);
  const linter = new LocalLinter({ binary, dialect });
  async function processRequest(v) {
    const { procName, args } = await serializer.deserialize(v);
    if (procName in linter) {
      const res = await linter[procName](...args);
      postMessage(await serializer.serializeArg(res));
    }
  }
  self.onmessage = (e2) => {
    if (isSerializedRequest(e2.data)) {
      processRequest(e2.data);
    }
  };
};
var __viteBrowserExternal = {};
var __viteBrowserExternal$1 = /* @__PURE__ */ Object.freeze({
  __proto__: null,
  default: __viteBrowserExternal
});
`,oe=typeof self<"u"&&self.Blob&&new Blob(["URL.revokeObjectURL(import.meta.url);",le],{type:"text/javascript;charset=utf-8"});function pt(r){let n;try{if(n=oe&&(self.URL||self.webkitURL).createObjectURL(oe),!n)throw"";let e=new Worker(n,{type:"module",name:r?.name});return e.addEventListener("error",()=>{(self.URL||self.webkitURL).revokeObjectURL(n)}),e}catch{return new Worker("data:text/javascript;charset=utf-8,"+encodeURIComponent(le),{type:"module",name:r?.name})}}var pn=class{constructor(n){$(this,"binary"),$(this,"serializer"),$(this,"dialect"),$(this,"worker"),$(this,"requestQueue"),$(this,"working",!0),$(this,"disposed",!1),this.binary=n.binary,this.serializer=new Fn(this.binary),this.dialect=n.dialect,this.worker=new pt,this.requestQueue=[],this.worker.onmessage=()=>{this.setupMainEventListeners(),this.worker.postMessage([this.binary.url,this.dialect,ae(this.binary)]),this.working=!1,this.submitRemainingRequests()}}setupMainEventListeners(){this.worker.onmessage=n=>{let{resolve:e}=this.requestQueue.shift();this.serializer.deserializeArg(n.data).then(t=>{e(t),this.working=!1,this.submitRemainingRequests()})},this.worker.onmessageerror=n=>{let{reject:e}=this.requestQueue.shift();e(n.data),this.working=!1,this.submitRemainingRequests()}}setup(){return this.rpc("setup",[])}lint(n,e){return this.rpc("lint",[n,e])}organizedLints(n,e){return this.rpc("organizedLints",[n,e])}applySuggestion(n,e,t){return this.rpc("applySuggestion",[n,e,t])}isLikelyEnglish(n){return this.rpc("isLikelyEnglish",[n])}isolateEnglish(n){return this.rpc("isolateEnglish",[n])}async getLintConfig(){return JSON.parse(await this.getLintConfigAsJSON())}setLintConfig(n){return this.setLintConfigWithJSON(JSON.stringify(n))}getLintConfigAsJSON(){return this.rpc("getLintConfigAsJSON",[])}setLintConfigWithJSON(n){return this.rpc("setLintConfigWithJSON",[n])}toTitleCase(n){return this.rpc("toTitleCase",[n])}getLintDescriptionsAsJSON(){return this.rpc("getLintDescriptionsAsJSON",[])}async getLintDescriptions(){return JSON.parse(await this.getLintDescriptionsAsJSON())}getLintDescriptionsHTMLAsJSON(){return this.rpc("getLintDescriptionsHTMLAsJSON",[])}async getLintDescriptionsHTML(){return JSON.parse(await this.getLintDescriptionsHTMLAsJSON())}getDefaultLintConfigAsJSON(){return this.rpc("getDefaultLintConfigAsJSON",[])}async getDefaultLintConfig(){return JSON.parse(await this.getDefaultLintConfigAsJSON())}async getStructuredLintConfig(){return JSON.parse(await this.getStructuredLintConfigJSON())}getStructuredLintConfigJSON(){return this.rpc("getStructuredLintConfigJSON",[])}async dispose(){this.disposed||(await this.rpc("dispose",[]),this.disposed=!0,this.requestQueue=[],this.worker.terminate())}ignoreLint(n,e){return this.ignoreLints(n,[e])}ignoreLints(n,e){return this.rpc("ignoreLints",[n,e])}ignoreLintHash(n){return this.rpc("ignoreLintHash",[n])}exportIgnoredLints(){return this.rpc("exportIgnoredLints",[])}importIgnoredLints(n){return this.rpc("importIgnoredLints",[n])}contextHash(n,e){return this.rpc("contextHash",[n,e])}clearIgnoredLints(){return this.rpc("clearIgnoredLints",[])}clearWords(){return this.rpc("clearWords",[])}importWords(n){return this.rpc("importWords",[n])}exportWords(){return this.rpc("exportWords",[])}getDialect(){return this.rpc("getDialect",[])}setDialect(n){return this.rpc("setDialect",[n])}summarizeStats(n,e){return this.rpc("summarizeStats",[n,e])}generateStatsFile(){return this.rpc("generateStatsFile",[])}importStatsFile(n){return this.rpc("importStatsFile",[n])}async loadWeirpackFromBlob(n){let e=new Uint8Array(await n.arrayBuffer()),t=Array.from(e);return await this.rpc("loadWeirpackFromBytes",[t])}async loadWeirpackFromBytes(n){let e=Array.from(n);return await this.rpc("loadWeirpackFromBytes",[e])}async rpc(n,e){if(this.disposed)throw new Error("WorkerLinter has been disposed.");return new Promise((i,_)=>{this.requestQueue.push({resolve:i,reject:_,request:{procName:n,args:e}}),this.submitRemainingRequests()})}async submitRemainingRequests(){if(!this.working)if(this.working=!0,this.requestQueue.length>0){let{request:n}=this.requestQueue[0],e=await this.serializer.serialize(n);this.worker.postMessage(e)}else this.working=!1}},G=Uint8Array,ce=Uint16Array,wt=Int32Array,bt=new G([0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0,0,0,0]),mt=new G([0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13,0,0]),Et=new G([16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15]),ge=function(r,n){for(var e=new ce(31),t=0;t<31;++t)e[t]=n+=1<<r[t-1];for(var i=new wt(e[30]),t=1;t<30;++t)for(var _=e[t];_<e[t+1];++_)i[_]=_-e[t]<<5|t;return{b:e,r:i}},fe=ge(bt,2),yt=fe.b,ht=fe.r;yt[28]=258,ht[258]=28;var ue=ge(mt,0),Ot=ue.b,Ft=ue.r,vt=new ce(32768);for(w=0;w<32768;++w)O=(w&43690)>>1|(w&21845)<<1,O=(O&52428)>>2|(O&13107)<<2,O=(O&61680)>>4|(O&3855)<<4,vt[w]=((O&65280)>>8|(O&255)<<8)>>1;var O,w;var wn=new G(288);for(w=0;w<144;++w)wn[w]=8;var w;for(w=144;w<256;++w)wn[w]=9;var w;for(w=256;w<280;++w)wn[w]=7;var w;for(w=280;w<288;++w)wn[w]=8;var w,St=new G(32);for(w=0;w<32;++w)St[w]=5;var w;var $t=new G(0);var jt=typeof TextDecoder<"u"&&new TextDecoder,xt=0;try{jt.decode($t,{stream:!0}),xt=1}catch{}function de(r){return r>=N.American&&r<=N.Indian?r:N.American}window.harperRuntime={createWorkerLinter(r,n){return new pn({binary:un(r,"slim"),dialect:de(n)})},createLocalLinter(r,n){return new dn({binary:un(r,"slim"),dialect:de(n)})}};})();
