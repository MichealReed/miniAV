(function dartProgram(){function copyProperties(a,b){var s=Object.keys(a)
for(var r=0;r<s.length;r++){var q=s[r]
b[q]=a[q]}}function mixinPropertiesHard(a,b){var s=Object.keys(a)
for(var r=0;r<s.length;r++){var q=s[r]
if(!b.hasOwnProperty(q)){b[q]=a[q]}}}function mixinPropertiesEasy(a,b){Object.assign(b,a)}var z=function(){var s=function(){}
s.prototype={p:{}}
var r=new s()
if(!(Object.getPrototypeOf(r)&&Object.getPrototypeOf(r).p===s.prototype.p))return false
try{if(typeof navigator!="undefined"&&typeof navigator.userAgent=="string"&&navigator.userAgent.indexOf("Chrome/")>=0)return true
if(typeof version=="function"&&version.length==0){var q=version()
if(/^\d+\.\d+\.\d+\.\d+$/.test(q))return true}}catch(p){}return false}()
function inherit(a,b){a.prototype.constructor=a
a.prototype["$i"+a.name]=a
if(b!=null){if(z){Object.setPrototypeOf(a.prototype,b.prototype)
return}var s=Object.create(b.prototype)
copyProperties(a.prototype,s)
a.prototype=s}}function inheritMany(a,b){for(var s=0;s<b.length;s++){inherit(b[s],a)}}function mixinEasy(a,b){mixinPropertiesEasy(b.prototype,a.prototype)
a.prototype.constructor=a}function mixinHard(a,b){mixinPropertiesHard(b.prototype,a.prototype)
a.prototype.constructor=a}function lazy(a,b,c,d){var s=a
a[b]=s
a[c]=function(){if(a[b]===s){a[b]=d()}a[c]=function(){return this[b]}
return a[b]}}function lazyFinal(a,b,c,d){var s=a
a[b]=s
a[c]=function(){if(a[b]===s){var r=d()
if(a[b]!==s){A.jt(b)}a[b]=r}var q=a[b]
a[c]=function(){return q}
return q}}function makeConstList(a,b){if(b!=null)A.z(a,b)
a.$flags=7
return a}function convertToFastObject(a){function t(){}t.prototype=a
new t()
return a}function convertAllToFastObject(a){for(var s=0;s<a.length;++s){convertToFastObject(a[s])}}var y=0
function instanceTearOffGetter(a,b){var s=null
return a?function(c){if(s===null)s=A.f0(b)
return new s(c,this)}:function(){if(s===null)s=A.f0(b)
return new s(this,null)}}function staticTearOffGetter(a){var s=null
return function(){if(s===null)s=A.f0(a).prototype
return s}}var x=0
function tearOffParameters(a,b,c,d,e,f,g,h,i,j){if(typeof h=="number"){h+=x}return{co:a,iS:b,iI:c,rC:d,dV:e,cs:f,fs:g,fT:h,aI:i||0,nDA:j}}function installStaticTearOff(a,b,c,d,e,f,g,h){var s=tearOffParameters(a,true,false,c,d,e,f,g,h,false)
var r=staticTearOffGetter(s)
a[b]=r}function installInstanceTearOff(a,b,c,d,e,f,g,h,i,j){c=!!c
var s=tearOffParameters(a,false,c,d,e,f,g,h,i,!!j)
var r=instanceTearOffGetter(c,s)
a[b]=r}function setOrUpdateInterceptorsByTag(a){var s=v.interceptorsByTag
if(!s){v.interceptorsByTag=a
return}copyProperties(a,s)}function setOrUpdateLeafTags(a){var s=v.leafTags
if(!s){v.leafTags=a
return}copyProperties(a,s)}function updateTypes(a){var s=v.types
var r=s.length
s.push.apply(s,a)
return r}function updateHolder(a,b){copyProperties(b,a)
return a}var hunkHelpers=function(){var s=function(a,b,c,d,e){return function(f,g,h,i){return installInstanceTearOff(f,g,a,b,c,d,[h],i,e,false)}},r=function(a,b,c,d){return function(e,f,g,h){return installStaticTearOff(e,f,a,b,c,[g],h,d)}}
return{inherit:inherit,inheritMany:inheritMany,mixin:mixinEasy,mixinHard:mixinHard,installStaticTearOff:installStaticTearOff,installInstanceTearOff:installInstanceTearOff,_instance_0u:s(0,0,null,["$0"],0),_instance_1u:s(0,1,null,["$1"],0),_instance_2u:s(0,2,null,["$2"],0),_instance_0i:s(1,0,null,["$0"],0),_instance_1i:s(1,1,null,["$1"],0),_instance_2i:s(1,2,null,["$2"],0),_static_0:r(0,null,["$0"],0),_static_1:r(1,null,["$1"],0),_static_2:r(2,null,["$2"],0),makeConstList:makeConstList,lazy:lazy,lazyFinal:lazyFinal,updateHolder:updateHolder,convertToFastObject:convertToFastObject,updateTypes:updateTypes,setOrUpdateInterceptorsByTag:setOrUpdateInterceptorsByTag,setOrUpdateLeafTags:setOrUpdateLeafTags}}()
function initializeDeferredHunk(a){x=v.types.length
a(hunkHelpers,v,w,$)}var J={
f5(a,b,c,d){return{i:a,p:b,e:c,x:d}},
ep(a){var s,r,q,p,o,n=a[v.dispatchPropertyName]
if(n==null)if($.f3==null){A.ji()
n=a[v.dispatchPropertyName]}if(n!=null){s=n.p
if(!1===s)return n.i
if(!0===s)return a
r=Object.getPrototypeOf(a)
if(s===r)return n.i
if(n.e===r)throw A.b(A.fz("Return interceptor for "+A.j(s(a,n))))}q=a.constructor
if(q==null)p=null
else{o=$.dX
if(o==null)o=$.dX=v.getIsolateTag("_$dart_js")
p=q[o]}if(p!=null)return p
p=A.jm(a)
if(p!=null)return p
if(typeof a=="function")return B.T
s=Object.getPrototypeOf(a)
if(s==null)return B.x
if(s===Object.prototype)return B.x
if(typeof q=="function"){o=$.dX
if(o==null)o=$.dX=v.getIsolateTag("_$dart_js")
Object.defineProperty(q,o,{value:B.k,enumerable:false,writable:true,configurable:true})
return B.k}return B.k},
ac(a){if(typeof a=="number"){if(Math.floor(a)==a)return J.bg.prototype
return J.cn.prototype}if(typeof a=="string")return J.aH.prototype
if(a==null)return J.bh.prototype
if(typeof a=="boolean")return J.cm.prototype
if(Array.isArray(a))return J.p.prototype
if(typeof a!="object"){if(typeof a=="function")return J.a7.prototype
if(typeof a=="symbol")return J.aJ.prototype
if(typeof a=="bigint")return J.aI.prototype
return a}if(a instanceof A.c)return a
return J.ep(a)},
h8(a){if(typeof a=="string")return J.aH.prototype
if(a==null)return a
if(Array.isArray(a))return J.p.prototype
if(typeof a!="object"){if(typeof a=="function")return J.a7.prototype
if(typeof a=="symbol")return J.aJ.prototype
if(typeof a=="bigint")return J.aI.prototype
return a}if(a instanceof A.c)return a
return J.ep(a)},
h9(a){if(a==null)return a
if(Array.isArray(a))return J.p.prototype
if(typeof a!="object"){if(typeof a=="function")return J.a7.prototype
if(typeof a=="symbol")return J.aJ.prototype
if(typeof a=="bigint")return J.aI.prototype
return a}if(a instanceof A.c)return a
return J.ep(a)},
je(a){if(a==null)return a
if(typeof a!="object"){if(typeof a=="function")return J.a7.prototype
if(typeof a=="symbol")return J.aJ.prototype
if(typeof a=="bigint")return J.aI.prototype
return a}if(a instanceof A.c)return a
return J.ep(a)},
eB(a,b){if(a==null)return b==null
if(typeof a!="object")return b!=null&&a===b
return J.ac(a).D(a,b)},
hv(a,b,c){return J.je(a).aV(a,b,c)},
P(a){return J.ac(a).gl(a)},
hw(a){return J.h9(a).gb_(a)},
eC(a){return J.h9(a).gu(a)},
f9(a){return J.h8(a).gp(a)},
b7(a){return J.ac(a).gk(a)},
aD(a){return J.ac(a).i(a)},
ck:function ck(){},
cm:function cm(){},
bh:function bh(){},
bj:function bj(){},
ag:function ag(){},
cs:function cs(){},
bC:function bC(){},
a7:function a7(){},
aI:function aI(){},
aJ:function aJ(){},
p:function p(a){this.$ti=a},
cl:function cl(){},
d8:function d8(a){this.$ti=a},
b8:function b8(a,b,c){var _=this
_.a=a
_.b=b
_.c=0
_.d=null
_.$ti=c},
bi:function bi(){},
bg:function bg(){},
cn:function cn(){},
aH:function aH(){}},A={eE:function eE(){},
M(a,b){a=a+b&536870911
a=a+((a&524287)<<10)&536870911
return a^a>>>6},
dm(a){a=a+((a&67108863)<<3)&536870911
a^=a>>>11
return a+((a&16383)<<15)&536870911},
f_(a,b,c){return a},
f4(a){var s,r
for(s=$.O.length,r=0;r<s;++r)if(a===$.O[r])return!0
return!1},
hK(a,b,c,d){if(t.x.b(a))return new A.bd(a,b,c.h("@<0>").t(d).h("bd<1,2>"))
return new A.as(a,b,c.h("@<0>").t(d).h("as<1,2>"))},
aK:function aK(a){this.a=a},
ev:function ev(){},
di:function di(){},
i:function i(){},
bo:function bo(a,b,c){var _=this
_.a=a
_.b=b
_.c=0
_.d=null
_.$ti=c},
as:function as(a,b,c){this.a=a
this.b=b
this.$ti=c},
bd:function bd(a,b,c){this.a=a
this.b=b
this.$ti=c},
bq:function bq(a,b,c){var _=this
_.a=null
_.b=a
_.c=b
_.$ti=c},
D:function D(){},
hh(a){var s=v.mangledGlobalNames[a]
if(s!=null)return s
return"minified:"+a},
jR(a,b){var s
if(b!=null){s=b.x
if(s!=null)return s}return t.aU.b(a)},
j(a){var s
if(typeof a=="string")return a
if(typeof a=="number"){if(a!==0)return""+a}else if(!0===a)return"true"
else if(!1===a)return"false"
else if(a==null)return"null"
s=J.aD(a)
return s},
bv(a){var s,r=$.fq
if(r==null)r=$.fq=Symbol("identityHashCode")
s=a[r]
if(s==null){s=Math.random()*0x3fffffff|0
a[r]=s}return s},
ct(a){var s,r,q,p
if(a instanceof A.c)return A.C(A.b5(a),null)
s=J.ac(a)
if(s===B.S||s===B.U||t.bI.b(a)){r=B.t(a)
if(r!=="Object"&&r!=="")return r
q=a.constructor
if(typeof q=="function"){p=q.name
if(typeof p=="string"&&p!=="Object"&&p!=="")return p}}return A.C(A.b5(a),null)},
fr(a){var s,r,q
if(a==null||typeof a=="number"||A.cT(a))return J.aD(a)
if(typeof a=="string")return JSON.stringify(a)
if(a instanceof A.af)return a.i(0)
if(a instanceof A.az)return a.aU(!0)
s=$.ht()
for(r=0;r<1;++r){q=s[r].bP(a)
if(q!=null)return q}return"Instance of '"+A.ct(a)+"'"},
y(a){var s
if(a<=65535)return String.fromCharCode(a)
if(a<=1114111){s=a-65536
return String.fromCharCode((B.c.aQ(s,10)|55296)>>>0,s&1023|56320)}throw A.b(A.bx(a,0,1114111,null,null))},
hM(a){var s=a.$thrownJsError
if(s==null)return null
return A.I(s)},
fs(a,b){var s
if(a.$thrownJsError==null){s=new Error()
A.w(a,s)
a.$thrownJsError=s
s.stack=b.i(0)}},
h(a,b){if(a==null)J.f9(a)
throw A.b(A.h7(a,b))},
h7(a,b){var s,r="index"
if(!A.eW(b))return new A.a4(!0,b,r,null)
s=A.F(J.f9(a))
if(b<0||b>=s)return A.fj(b,s,a,r)
return A.ft(b,r)},
j9(a,b,c){if(a>c)return A.bx(a,0,c,"start",null)
if(b!=null)if(b<a||b>c)return A.bx(b,a,c,"end",null)
return new A.a4(!0,b,"end",null)},
b(a){return A.w(a,new Error())},
w(a,b){var s
if(a==null)a=new A.a9()
b.dartException=a
s=A.ju
if("defineProperty" in Object){Object.defineProperty(b,"message",{get:s})
b.name=""}else b.toString=s
return b},
ju(){return J.aD(this.dartException)},
ad(a,b){throw A.w(a,b==null?new Error():b)},
ae(a,b,c){var s
if(b==null)b=0
if(c==null)c=0
s=Error()
A.ad(A.ir(a,b,c),s)},
ir(a,b,c){var s,r,q,p,o,n,m,l,k
if(typeof b=="string")s=b
else{r="[]=;add;removeWhere;retainWhere;removeRange;setRange;setInt8;setInt16;setInt32;setUint8;setUint16;setUint32;setFloat32;setFloat64".split(";")
q=r.length
p=b
if(p>q){c=p/q|0
p%=q}s=r[p]}o=typeof c=="string"?c:"modify;remove from;add to".split(";")[c]
n=t.j.b(a)?"list":"ByteData"
m=a.$flags|0
l="a "
if((m&4)!==0)k="constant "
else if((m&2)!==0){k="unmodifiable "
l="an "}else k=(m&1)!==0?"fixed-length ":""
return new A.bD("'"+s+"': Cannot "+o+" "+l+k+n)},
an(a){throw A.b(A.ce(a))},
aa(a){var s,r,q,p,o,n
a=A.hg(a.replace(String({}),"$receiver$"))
s=a.match(/\\\$[a-zA-Z]+\\\$/g)
if(s==null)s=A.z([],t.s)
r=s.indexOf("\\$arguments\\$")
q=s.indexOf("\\$argumentsExpr\\$")
p=s.indexOf("\\$expr\\$")
o=s.indexOf("\\$method\\$")
n=s.indexOf("\\$receiver\\$")
return new A.dn(a.replace(new RegExp("\\\\\\$arguments\\\\\\$","g"),"((?:x|[^x])*)").replace(new RegExp("\\\\\\$argumentsExpr\\\\\\$","g"),"((?:x|[^x])*)").replace(new RegExp("\\\\\\$expr\\\\\\$","g"),"((?:x|[^x])*)").replace(new RegExp("\\\\\\$method\\\\\\$","g"),"((?:x|[^x])*)").replace(new RegExp("\\\\\\$receiver\\\\\\$","g"),"((?:x|[^x])*)"),r,q,p,o,n)},
dp(a){return function($expr$){var $argumentsExpr$="$arguments$"
try{$expr$.$method$($argumentsExpr$)}catch(s){return s.message}}(a)},
fy(a){return function($expr$){try{$expr$.$method$}catch(s){return s.message}}(a)},
eF(a,b){var s=b==null,r=s?null:b.method
return new A.co(a,r,s?null:b.receiver)},
H(a){var s
if(a==null)return new A.dh(a)
if(a instanceof A.bf){s=a.a
return A.am(a,s==null?A.T(s):s)}if(typeof a!=="object")return a
if("dartException" in a)return A.am(a,a.dartException)
return A.iZ(a)},
am(a,b){if(t.C.b(b))if(b.$thrownJsError==null)b.$thrownJsError=a
return b},
iZ(a){var s,r,q,p,o,n,m,l,k,j,i,h,g
if(!("message" in a))return a
s=a.message
if("number" in a&&typeof a.number=="number"){r=a.number
q=r&65535
if((B.c.aQ(r,16)&8191)===10)switch(q){case 438:return A.am(a,A.eF(A.j(s)+" (Error "+q+")",null))
case 445:case 5007:A.j(s)
return A.am(a,new A.bu())}}if(a instanceof TypeError){p=$.hi()
o=$.hj()
n=$.hk()
m=$.hl()
l=$.ho()
k=$.hp()
j=$.hn()
$.hm()
i=$.hr()
h=$.hq()
g=p.A(s)
if(g!=null)return A.am(a,A.eF(A.a2(s),g))
else{g=o.A(s)
if(g!=null){g.method="call"
return A.am(a,A.eF(A.a2(s),g))}else if(n.A(s)!=null||m.A(s)!=null||l.A(s)!=null||k.A(s)!=null||j.A(s)!=null||m.A(s)!=null||i.A(s)!=null||h.A(s)!=null){A.a2(s)
return A.am(a,new A.bu())}}return A.am(a,new A.cB(typeof s=="string"?s:""))}if(a instanceof RangeError){if(typeof s=="string"&&s.indexOf("call stack")!==-1)return new A.bz()
s=function(b){try{return String(b)}catch(f){}return null}(a)
return A.am(a,new A.a4(!1,null,null,typeof s=="string"?s.replace(/^RangeError:\s*/,""):s))}if(typeof InternalError=="function"&&a instanceof InternalError)if(typeof s=="string"&&s==="too much recursion")return new A.bz()
return a},
I(a){var s
if(a instanceof A.bf)return a.b
if(a==null)return new A.bP(a)
s=a.$cachedTrace
if(s!=null)return s
s=new A.bP(a)
if(typeof a==="object")a.$cachedTrace=s
return s},
hc(a){if(a==null)return J.P(a)
if(typeof a=="object")return A.bv(a)
return J.P(a)},
jd(a,b){var s,r,q,p=a.length
for(s=0;s<p;s=q){r=s+1
q=r+1
b.E(0,a[s],a[r])}return b},
iA(a,b,c,d,e,f){t.Z.a(a)
switch(A.F(b)){case 0:return a.$0()
case 1:return a.$1(c)
case 2:return a.$2(c,d)
case 3:return a.$3(c,d,e)
case 4:return a.$4(c,d,e,f)}throw A.b(new A.dH("Unsupported number of arguments for wrapped closure"))},
c4(a,b){var s=a.$identity
if(!!s)return s
s=A.j6(a,b)
a.$identity=s
return s},
j6(a,b){var s
switch(b){case 0:s=a.$0
break
case 1:s=a.$1
break
case 2:s=a.$2
break
case 3:s=a.$3
break
case 4:s=a.$4
break
default:s=null}if(s!=null)return s.bind(a)
return function(c,d,e){return function(f,g,h,i){return e(c,d,f,g,h,i)}}(a,b,A.iA)},
hD(a2){var s,r,q,p,o,n,m,l,k,j,i=a2.co,h=a2.iS,g=a2.iI,f=a2.nDA,e=a2.aI,d=a2.fs,c=a2.cs,b=d[0],a=c[0],a0=i[b],a1=a2.fT
a1.toString
s=h?Object.create(new A.cx().constructor.prototype):Object.create(new A.aF(null,null).constructor.prototype)
s.$initialize=s.constructor
r=h?function static_tear_off(){this.$initialize()}:function tear_off(a3,a4){this.$initialize(a3,a4)}
s.constructor=r
r.prototype=s
s.$_name=b
s.$_target=a0
q=!h
if(q)p=A.ff(b,a0,g,f)
else{s.$static_name=b
p=a0}s.$S=A.hz(a1,h,g)
s[a]=p
for(o=p,n=1;n<d.length;++n){m=d[n]
if(typeof m=="string"){l=i[m]
k=m
m=l}else k=""
j=c[n]
if(j!=null){if(q)m=A.ff(k,m,g,f)
s[j]=m}if(n===e)o=m}s.$C=o
s.$R=a2.rC
s.$D=a2.dV
return r},
hz(a,b,c){if(typeof a=="number")return a
if(typeof a=="string"){if(b)throw A.b("Cannot compute signature for static tearoff.")
return function(d,e){return function(){return e(this,d)}}(a,A.hx)}throw A.b("Error in functionType of tearoff")},
hA(a,b,c,d){var s=A.fd
switch(b?-1:a){case 0:return function(e,f){return function(){return f(this)[e]()}}(c,s)
case 1:return function(e,f){return function(g){return f(this)[e](g)}}(c,s)
case 2:return function(e,f){return function(g,h){return f(this)[e](g,h)}}(c,s)
case 3:return function(e,f){return function(g,h,i){return f(this)[e](g,h,i)}}(c,s)
case 4:return function(e,f){return function(g,h,i,j){return f(this)[e](g,h,i,j)}}(c,s)
case 5:return function(e,f){return function(g,h,i,j,k){return f(this)[e](g,h,i,j,k)}}(c,s)
default:return function(e,f){return function(){return e.apply(f(this),arguments)}}(d,s)}},
ff(a,b,c,d){if(c)return A.hC(a,b,d)
return A.hA(b.length,d,a,b)},
hB(a,b,c,d){var s=A.fd,r=A.hy
switch(b?-1:a){case 0:throw A.b(new A.cu("Intercepted function with no arguments."))
case 1:return function(e,f,g){return function(){return f(this)[e](g(this))}}(c,r,s)
case 2:return function(e,f,g){return function(h){return f(this)[e](g(this),h)}}(c,r,s)
case 3:return function(e,f,g){return function(h,i){return f(this)[e](g(this),h,i)}}(c,r,s)
case 4:return function(e,f,g){return function(h,i,j){return f(this)[e](g(this),h,i,j)}}(c,r,s)
case 5:return function(e,f,g){return function(h,i,j,k){return f(this)[e](g(this),h,i,j,k)}}(c,r,s)
case 6:return function(e,f,g){return function(h,i,j,k,l){return f(this)[e](g(this),h,i,j,k,l)}}(c,r,s)
default:return function(e,f,g){return function(){var q=[g(this)]
Array.prototype.push.apply(q,arguments)
return e.apply(f(this),q)}}(d,r,s)}},
hC(a,b,c){var s,r
if($.fb==null)$.fb=A.fa("interceptor")
if($.fc==null)$.fc=A.fa("receiver")
s=b.length
r=A.hB(s,c,a,b)
return r},
f0(a){return A.hD(a)},
hx(a,b){return A.bY(v.typeUniverse,A.b5(a.a),b)},
fd(a){return a.a},
hy(a){return a.b},
fa(a){var s,r,q,p=new A.aF("receiver","interceptor"),o=Object.getOwnPropertyNames(p)
o.$flags=1
s=o
for(o=s.length,r=0;r<o;++r){q=s[r]
if(p[q]===a)return q}throw A.b(A.c5("Field name "+a+" not found.",null))},
jf(a){return v.getIsolateTag(a)},
jQ(a,b,c){Object.defineProperty(a,b,{value:c,enumerable:false,writable:true,configurable:true})},
jm(a){var s,r,q,p,o,n=A.a2($.hb.$1(a)),m=$.eo[n]
if(m!=null){Object.defineProperty(a,v.dispatchPropertyName,{value:m,enumerable:false,writable:true,configurable:true})
return m.i}s=$.et[n]
if(s!=null)return s
r=v.interceptorsByTag[n]
if(r==null){q=A.ef($.h5.$2(a,n))
if(q!=null){m=$.eo[q]
if(m!=null){Object.defineProperty(a,v.dispatchPropertyName,{value:m,enumerable:false,writable:true,configurable:true})
return m.i}s=$.et[q]
if(s!=null)return s
r=v.interceptorsByTag[q]
n=q}}if(r==null)return null
s=r.prototype
p=n[0]
if(p==="!"){m=A.eu(s)
$.eo[n]=m
Object.defineProperty(a,v.dispatchPropertyName,{value:m,enumerable:false,writable:true,configurable:true})
return m.i}if(p==="~"){$.et[n]=s
return s}if(p==="-"){o=A.eu(s)
Object.defineProperty(Object.getPrototypeOf(a),v.dispatchPropertyName,{value:o,enumerable:false,writable:true,configurable:true})
return o.i}if(p==="+")return A.hd(a,s)
if(p==="*")throw A.b(A.fz(n))
if(v.leafTags[n]===true){o=A.eu(s)
Object.defineProperty(Object.getPrototypeOf(a),v.dispatchPropertyName,{value:o,enumerable:false,writable:true,configurable:true})
return o.i}else return A.hd(a,s)},
hd(a,b){var s=Object.getPrototypeOf(a)
Object.defineProperty(s,v.dispatchPropertyName,{value:J.f5(b,s,null,null),enumerable:false,writable:true,configurable:true})
return b},
eu(a){return J.f5(a,!1,null,!!a.$iK)},
jo(a,b,c){var s=b.prototype
if(v.leafTags[a]===true)return A.eu(s)
else return J.f5(s,c,null,null)},
ji(){if(!0===$.f3)return
$.f3=!0
A.jj()},
jj(){var s,r,q,p,o,n,m,l
$.eo=Object.create(null)
$.et=Object.create(null)
A.jh()
s=v.interceptorsByTag
r=Object.getOwnPropertyNames(s)
if(typeof window!="undefined"){window
q=function(){}
for(p=0;p<r.length;++p){o=r[p]
n=$.hf.$1(o)
if(n!=null){m=A.jo(o,s[o],n)
if(m!=null){Object.defineProperty(n,v.dispatchPropertyName,{value:m,enumerable:false,writable:true,configurable:true})
q.prototype=n}}}}for(p=0;p<r.length;++p){o=r[p]
if(/^[A-Za-z_]/.test(o)){l=s[o]
s["!"+o]=l
s["~"+o]=l
s["-"+o]=l
s["+"+o]=l
s["*"+o]=l}}},
jh(){var s,r,q,p,o,n,m=B.G()
m=A.b4(B.H,A.b4(B.I,A.b4(B.u,A.b4(B.u,A.b4(B.J,A.b4(B.K,A.b4(B.L(B.t),m)))))))
if(typeof dartNativeDispatchHooksTransformer!="undefined"){s=dartNativeDispatchHooksTransformer
if(typeof s=="function")s=[s]
if(Array.isArray(s))for(r=0;r<s.length;++r){q=s[r]
if(typeof q=="function")m=q(m)||m}}p=m.getTag
o=m.getUnknownTag
n=m.prototypeForTag
$.hb=new A.eq(p)
$.h5=new A.er(o)
$.hf=new A.es(n)},
b4(a,b){return a(b)||b},
j8(a,b){var s=b.length,r=v.rttc[""+s+";"+a]
if(r==null)return null
if(s===0)return r
if(s===r.length)return r.apply(null,b)
return r(b)},
jb(a){if(a.indexOf("$",0)>=0)return a.replace(/\$/g,"$$$$")
return a},
hg(a){if(/[[\]{}()*+?.\\^$|]/.test(a))return a.replace(/[[\]{}()*+?.\\^$|]/g,"\\$&")
return a},
f6(a,b,c){var s=A.js(a,b,c)
return s},
js(a,b,c){var s,r,q
if(b===""){if(a==="")return c
s=a.length
for(r=c,q=0;q<s;++q)r=r+a[q]+c
return r.charCodeAt(0)==0?r:r}if(a.indexOf(b,0)<0)return a
if(a.length<500||c.indexOf("$",0)>=0)return a.split(b).join(c)
return a.replace(new RegExp(A.hg(b),"g"),A.jb(c))},
bO:function bO(a,b){this.a=a
this.b=b},
ba:function ba(){},
bb:function bb(a,b,c){this.a=a
this.b=b
this.$ti=c},
bI:function bI(a,b){this.a=a
this.$ti=b},
bJ:function bJ(a,b,c){var _=this
_.a=a
_.b=b
_.c=0
_.d=null
_.$ti=c},
by:function by(){},
dn:function dn(a,b,c,d,e,f){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f},
bu:function bu(){},
co:function co(a,b,c){this.a=a
this.b=b
this.c=c},
cB:function cB(a){this.a=a},
dh:function dh(a){this.a=a},
bf:function bf(a,b){this.a=a
this.b=b},
bP:function bP(a){this.a=a
this.b=null},
af:function af(){},
c9:function c9(){},
ca:function ca(){},
cz:function cz(){},
cx:function cx(){},
aF:function aF(a,b){this.a=a
this.b=b},
cu:function cu(a){this.a=a},
ap:function ap(a){var _=this
_.a=0
_.f=_.e=_.d=_.c=_.b=null
_.r=0
_.$ti=a},
da:function da(a,b){this.a=a
this.b=b
this.c=null},
bn:function bn(a,b){this.a=a
this.$ti=b},
aq:function aq(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=null
_.$ti=d},
bl:function bl(a,b){this.a=a
this.$ti=b},
bm:function bm(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=null
_.$ti=d},
eq:function eq(a){this.a=a},
er:function er(a){this.a=a},
es:function es(a){this.a=a},
az:function az(){},
b_:function b_(){},
jt(a){throw A.w(new A.aK("Field '"+a+"' has been assigned during initialization."),new Error())},
hZ(){var s=new A.dG()
return s.b=s},
dG:function dG(){this.b=null},
fT(a){return a},
hL(a,b,c){var s=new DataView(a,b,c)
return s},
io(a,b,c){var s
if(!(a>>>0!==a))s=b>>>0!==b||a>b||b>c
else s=!0
if(s)throw A.b(A.j9(a,b,c))
return b},
ah:function ah(){},
aL:function aL(){},
bt:function bt(){},
cP:function cP(a){this.a=a},
aM:function aM(){},
aS:function aS(){},
br:function br(){},
bs:function bs(){},
aN:function aN(){},
aO:function aO(){},
aP:function aP(){},
aQ:function aQ(){},
aR:function aR(){},
aT:function aT(){},
aU:function aU(){},
at:function at(){},
ai:function ai(){},
bK:function bK(){},
bL:function bL(){},
bM:function bM(){},
bN:function bN(){},
eJ(a,b){var s=b.c
return s==null?b.c=A.bW(a,"A",[b.x]):s},
fu(a){var s=a.w
if(s===6||s===7)return A.fu(a.x)
return s===11||s===12},
hO(a){return a.as},
al(a){return A.e8(v.typeUniverse,a,!1)},
aA(a1,a2,a3,a4){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0=a2.w
switch(a0){case 5:case 1:case 2:case 3:case 4:return a2
case 6:s=a2.x
r=A.aA(a1,s,a3,a4)
if(r===s)return a2
return A.fL(a1,r,!0)
case 7:s=a2.x
r=A.aA(a1,s,a3,a4)
if(r===s)return a2
return A.fK(a1,r,!0)
case 8:q=a2.y
p=A.b3(a1,q,a3,a4)
if(p===q)return a2
return A.bW(a1,a2.x,p)
case 9:o=a2.x
n=A.aA(a1,o,a3,a4)
m=a2.y
l=A.b3(a1,m,a3,a4)
if(n===o&&l===m)return a2
return A.eO(a1,n,l)
case 10:k=a2.x
j=a2.y
i=A.b3(a1,j,a3,a4)
if(i===j)return a2
return A.fM(a1,k,i)
case 11:h=a2.x
g=A.aA(a1,h,a3,a4)
f=a2.y
e=A.iV(a1,f,a3,a4)
if(g===h&&e===f)return a2
return A.fJ(a1,g,e)
case 12:d=a2.y
a4+=d.length
c=A.b3(a1,d,a3,a4)
o=a2.x
n=A.aA(a1,o,a3,a4)
if(c===d&&n===o)return a2
return A.eP(a1,n,c,!0)
case 13:b=a2.x
if(b<a4)return a2
a=a3[b-a4]
if(a==null)return a2
return a
default:throw A.b(A.c7("Attempted to substitute unexpected RTI kind "+a0))}},
b3(a,b,c,d){var s,r,q,p,o=b.length,n=A.ea(o)
for(s=!1,r=0;r<o;++r){q=b[r]
p=A.aA(a,q,c,d)
if(p!==q)s=!0
n[r]=p}return s?n:b},
iW(a,b,c,d){var s,r,q,p,o,n,m=b.length,l=A.ea(m)
for(s=!1,r=0;r<m;r+=3){q=b[r]
p=b[r+1]
o=b[r+2]
n=A.aA(a,o,c,d)
if(n!==o)s=!0
l.splice(r,3,q,p,n)}return s?l:b},
iV(a,b,c,d){var s,r=b.a,q=A.b3(a,r,c,d),p=b.b,o=A.b3(a,p,c,d),n=b.c,m=A.iW(a,n,c,d)
if(q===r&&o===p&&m===n)return b
s=new A.cL()
s.a=q
s.b=o
s.c=m
return s},
z(a,b){a[v.arrayRti]=b
return a},
f1(a){var s=a.$S
if(s!=null){if(typeof s=="number")return A.jg(s)
return a.$S()}return null},
jk(a,b){var s
if(A.fu(b))if(a instanceof A.af){s=A.f1(a)
if(s!=null)return s}return A.b5(a)},
b5(a){if(a instanceof A.c)return A.o(a)
if(Array.isArray(a))return A.c0(a)
return A.eU(J.ac(a))},
c0(a){var s=a[v.arrayRti],r=t.gn
if(s==null)return r
if(s.constructor!==r.constructor)return r
return s},
o(a){var s=a.$ti
return s!=null?s:A.eU(a)},
eU(a){var s=a.constructor,r=s.$ccache
if(r!=null)return r
return A.iy(a,s)},
iy(a,b){var s=a instanceof A.af?Object.getPrototypeOf(Object.getPrototypeOf(a)).constructor:b,r=A.ig(v.typeUniverse,s.name)
b.$ccache=r
return r},
jg(a){var s,r=v.types,q=r[a]
if(typeof q=="string"){s=A.e8(v.typeUniverse,q,!1)
r[a]=s
return s}return q},
ha(a){return A.a3(A.o(a))},
eY(a){var s
if(a instanceof A.az)return a.aJ()
s=a instanceof A.af?A.f1(a):null
if(s!=null)return s
if(t.dm.b(a))return J.b7(a).a
if(Array.isArray(a))return A.c0(a)
return A.b5(a)},
a3(a){var s=a.r
return s==null?a.r=new A.e7(a):s},
jc(a,b){var s,r,q=b,p=q.length
if(p===0)return t.bQ
if(0>=p)return A.h(q,0)
s=A.bY(v.typeUniverse,A.eY(q[0]),"@<0>")
for(r=1;r<p;++r){if(!(r<q.length))return A.h(q,r)
s=A.fN(v.typeUniverse,s,A.eY(q[r]))}return A.bY(v.typeUniverse,s,a)},
Z(a){return A.a3(A.e8(v.typeUniverse,a,!1))},
ix(a){var s=this
s.b=A.iT(s)
return s.b(a)},
iT(a){var s,r,q,p,o
if(a===t.K)return A.iG
if(A.aB(a))return A.iK
s=a.w
if(s===6)return A.iv
if(s===1)return A.fZ
if(s===7)return A.iB
r=A.iS(a)
if(r!=null)return r
if(s===8){q=a.x
if(a.y.every(A.aB)){a.f="$i"+q
if(q==="m")return A.iE
if(a===t.m)return A.iD
return A.iJ}}else if(s===10){p=A.j8(a.x,a.y)
o=p==null?A.fZ:p
return o==null?A.T(o):o}return A.it},
iS(a){if(a.w===8){if(a===t.S)return A.eW
if(a===t.i||a===t.o)return A.iF
if(a===t.N)return A.iI
if(a===t.y)return A.cT}return null},
iw(a){var s=this,r=A.is
if(A.aB(s))r=A.ik
else if(s===t.K)r=A.T
else if(A.b6(s)){r=A.iu
if(s===t.h6)r=A.cR
else if(s===t.c8)r=A.ef
else if(s===t.u)r=A.ii
else if(s===t.cg)r=A.fR
else if(s===t.cD)r=A.ij
else if(s===t.bX)r=A.eR}else if(s===t.S)r=A.F
else if(s===t.N)r=A.a2
else if(s===t.y)r=A.eQ
else if(s===t.o)r=A.fQ
else if(s===t.i)r=A.ee
else if(s===t.m)r=A.G
s.a=r
return s.a(a)},
it(a){var s=this
if(a==null)return A.b6(s)
return A.jl(v.typeUniverse,A.jk(a,s),s)},
iv(a){if(a==null)return!0
return this.x.b(a)},
iJ(a){var s,r=this
if(a==null)return A.b6(r)
s=r.f
if(a instanceof A.c)return!!a[s]
return!!J.ac(a)[s]},
iE(a){var s,r=this
if(a==null)return A.b6(r)
if(typeof a!="object")return!1
if(Array.isArray(a))return!0
s=r.f
if(a instanceof A.c)return!!a[s]
return!!J.ac(a)[s]},
iD(a){var s=this
if(a==null)return!1
if(typeof a=="object"){if(a instanceof A.c)return!!a[s.f]
return!0}if(typeof a=="function")return!0
return!1},
fY(a){if(typeof a=="object"){if(a instanceof A.c)return t.m.b(a)
return!0}if(typeof a=="function")return!0
return!1},
is(a){var s=this
if(a==null){if(A.b6(s))return a}else if(s.b(a))return a
throw A.w(A.fU(a,s),new Error())},
iu(a){var s=this
if(a==null||s.b(a))return a
throw A.w(A.fU(a,s),new Error())},
fU(a,b){return new A.bU("TypeError: "+A.fB(a,A.C(b,null)))},
fB(a,b){return A.ch(a)+": type '"+A.C(A.eY(a),null)+"' is not a subtype of type '"+b+"'"},
S(a,b){return new A.bU("TypeError: "+A.fB(a,b))},
iB(a){var s=this
return s.x.b(a)||A.eJ(v.typeUniverse,s).b(a)},
iG(a){return a!=null},
T(a){if(a!=null)return a
throw A.w(A.S(a,"Object"),new Error())},
iK(a){return!0},
ik(a){return a},
fZ(a){return!1},
cT(a){return!0===a||!1===a},
eQ(a){if(!0===a)return!0
if(!1===a)return!1
throw A.w(A.S(a,"bool"),new Error())},
ii(a){if(!0===a)return!0
if(!1===a)return!1
if(a==null)return a
throw A.w(A.S(a,"bool?"),new Error())},
ee(a){if(typeof a=="number")return a
throw A.w(A.S(a,"double"),new Error())},
ij(a){if(typeof a=="number")return a
if(a==null)return a
throw A.w(A.S(a,"double?"),new Error())},
eW(a){return typeof a=="number"&&Math.floor(a)===a},
F(a){if(typeof a=="number"&&Math.floor(a)===a)return a
throw A.w(A.S(a,"int"),new Error())},
cR(a){if(typeof a=="number"&&Math.floor(a)===a)return a
if(a==null)return a
throw A.w(A.S(a,"int?"),new Error())},
iF(a){return typeof a=="number"},
fQ(a){if(typeof a=="number")return a
throw A.w(A.S(a,"num"),new Error())},
fR(a){if(typeof a=="number")return a
if(a==null)return a
throw A.w(A.S(a,"num?"),new Error())},
iI(a){return typeof a=="string"},
a2(a){if(typeof a=="string")return a
throw A.w(A.S(a,"String"),new Error())},
ef(a){if(typeof a=="string")return a
if(a==null)return a
throw A.w(A.S(a,"String?"),new Error())},
G(a){if(A.fY(a))return a
throw A.w(A.S(a,"JSObject"),new Error())},
eR(a){if(a==null)return a
if(A.fY(a))return a
throw A.w(A.S(a,"JSObject?"),new Error())},
h2(a,b){var s,r,q
for(s="",r="",q=0;q<a.length;++q,r=", ")s+=r+A.C(a[q],b)
return s},
iO(a,b){var s,r,q,p,o,n,m=a.x,l=a.y
if(""===m)return"("+A.h2(l,b)+")"
s=l.length
r=m.split(",")
q=r.length-s
for(p="(",o="",n=0;n<s;++n,o=", "){p+=o
if(q===0)p+="{"
p+=A.C(l[n],b)
if(q>=0)p+=" "+r[q];++q}return p+"})"},
fV(a3,a4,a5){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1=", ",a2=null
if(a5!=null){s=a5.length
if(a4==null)a4=A.z([],t.s)
else a2=a4.length
r=a4.length
for(q=s;q>0;--q)B.a.j(a4,"T"+(r+q))
for(p=t.X,o="<",n="",q=0;q<s;++q,n=a1){m=a4.length
l=m-1-q
if(!(l>=0))return A.h(a4,l)
o=o+n+a4[l]
k=a5[q]
j=k.w
if(!(j===2||j===3||j===4||j===5||k===p))o+=" extends "+A.C(k,a4)}o+=">"}else o=""
p=a3.x
i=a3.y
h=i.a
g=h.length
f=i.b
e=f.length
d=i.c
c=d.length
b=A.C(p,a4)
for(a="",a0="",q=0;q<g;++q,a0=a1)a+=a0+A.C(h[q],a4)
if(e>0){a+=a0+"["
for(a0="",q=0;q<e;++q,a0=a1)a+=a0+A.C(f[q],a4)
a+="]"}if(c>0){a+=a0+"{"
for(a0="",q=0;q<c;q+=3,a0=a1){a+=a0
if(d[q+1])a+="required "
a+=A.C(d[q+2],a4)+" "+d[q]}a+="}"}if(a2!=null){a4.toString
a4.length=a2}return o+"("+a+") => "+b},
C(a,b){var s,r,q,p,o,n,m,l=a.w
if(l===5)return"erased"
if(l===2)return"dynamic"
if(l===3)return"void"
if(l===1)return"Never"
if(l===4)return"any"
if(l===6){s=a.x
r=A.C(s,b)
q=s.w
return(q===11||q===12?"("+r+")":r)+"?"}if(l===7)return"FutureOr<"+A.C(a.x,b)+">"
if(l===8){p=A.iY(a.x)
o=a.y
return o.length>0?p+("<"+A.h2(o,b)+">"):p}if(l===10)return A.iO(a,b)
if(l===11)return A.fV(a,b,null)
if(l===12)return A.fV(a.x,b,a.y)
if(l===13){n=a.x
m=b.length
n=m-1-n
if(!(n>=0&&n<m))return A.h(b,n)
return b[n]}return"?"},
iY(a){var s=v.mangledGlobalNames[a]
if(s!=null)return s
return"minified:"+a},
ih(a,b){var s=a.tR[b]
while(typeof s=="string")s=a.tR[s]
return s},
ig(a,b){var s,r,q,p,o,n=a.eT,m=n[b]
if(m==null)return A.e8(a,b,!1)
else if(typeof m=="number"){s=m
r=A.bX(a,5,"#")
q=A.ea(s)
for(p=0;p<s;++p)q[p]=r
o=A.bW(a,b,q)
n[b]=o
return o}else return m},
ie(a,b){return A.fO(a.tR,b)},
id(a,b){return A.fO(a.eT,b)},
e8(a,b,c){var s,r=a.eC,q=r.get(b)
if(q!=null)return q
s=A.fF(A.fD(a,null,b,!1))
r.set(b,s)
return s},
bY(a,b,c){var s,r,q=b.z
if(q==null)q=b.z=new Map()
s=q.get(c)
if(s!=null)return s
r=A.fF(A.fD(a,b,c,!0))
q.set(c,r)
return r},
fN(a,b,c){var s,r,q,p=b.Q
if(p==null)p=b.Q=new Map()
s=c.as
r=p.get(s)
if(r!=null)return r
q=A.eO(a,b,c.w===9?c.y:[c])
p.set(s,q)
return q},
ak(a,b){b.a=A.iw
b.b=A.ix
return b},
bX(a,b,c){var s,r,q=a.eC.get(c)
if(q!=null)return q
s=new A.a_(null,null)
s.w=b
s.as=c
r=A.ak(a,s)
a.eC.set(c,r)
return r},
fL(a,b,c){var s,r=b.as+"?",q=a.eC.get(r)
if(q!=null)return q
s=A.ib(a,b,r,c)
a.eC.set(r,s)
return s},
ib(a,b,c,d){var s,r,q
if(d){s=b.w
r=!0
if(!A.aB(b))if(!(b===t.P||b===t.T))if(s!==6)r=s===7&&A.b6(b.x)
if(r)return b
else if(s===1)return t.P}q=new A.a_(null,null)
q.w=6
q.x=b
q.as=c
return A.ak(a,q)},
fK(a,b,c){var s,r=b.as+"/",q=a.eC.get(r)
if(q!=null)return q
s=A.i9(a,b,r,c)
a.eC.set(r,s)
return s},
i9(a,b,c,d){var s,r
if(d){s=b.w
if(A.aB(b)||b===t.K)return b
else if(s===1)return A.bW(a,"A",[b])
else if(b===t.P||b===t.T)return t.eH}r=new A.a_(null,null)
r.w=7
r.x=b
r.as=c
return A.ak(a,r)},
ic(a,b){var s,r,q=""+b+"^",p=a.eC.get(q)
if(p!=null)return p
s=new A.a_(null,null)
s.w=13
s.x=b
s.as=q
r=A.ak(a,s)
a.eC.set(q,r)
return r},
bV(a){var s,r,q,p=a.length
for(s="",r="",q=0;q<p;++q,r=",")s+=r+a[q].as
return s},
i8(a){var s,r,q,p,o,n=a.length
for(s="",r="",q=0;q<n;q+=3,r=","){p=a[q]
o=a[q+1]?"!":":"
s+=r+p+o+a[q+2].as}return s},
bW(a,b,c){var s,r,q,p=b
if(c.length>0)p+="<"+A.bV(c)+">"
s=a.eC.get(p)
if(s!=null)return s
r=new A.a_(null,null)
r.w=8
r.x=b
r.y=c
if(c.length>0)r.c=c[0]
r.as=p
q=A.ak(a,r)
a.eC.set(p,q)
return q},
eO(a,b,c){var s,r,q,p,o,n
if(b.w===9){s=b.x
r=b.y.concat(c)}else{r=c
s=b}q=s.as+(";<"+A.bV(r)+">")
p=a.eC.get(q)
if(p!=null)return p
o=new A.a_(null,null)
o.w=9
o.x=s
o.y=r
o.as=q
n=A.ak(a,o)
a.eC.set(q,n)
return n},
fM(a,b,c){var s,r,q="+"+(b+"("+A.bV(c)+")"),p=a.eC.get(q)
if(p!=null)return p
s=new A.a_(null,null)
s.w=10
s.x=b
s.y=c
s.as=q
r=A.ak(a,s)
a.eC.set(q,r)
return r},
fJ(a,b,c){var s,r,q,p,o,n=b.as,m=c.a,l=m.length,k=c.b,j=k.length,i=c.c,h=i.length,g="("+A.bV(m)
if(j>0){s=l>0?",":""
g+=s+"["+A.bV(k)+"]"}if(h>0){s=l>0?",":""
g+=s+"{"+A.i8(i)+"}"}r=n+(g+")")
q=a.eC.get(r)
if(q!=null)return q
p=new A.a_(null,null)
p.w=11
p.x=b
p.y=c
p.as=r
o=A.ak(a,p)
a.eC.set(r,o)
return o},
eP(a,b,c,d){var s,r=b.as+("<"+A.bV(c)+">"),q=a.eC.get(r)
if(q!=null)return q
s=A.ia(a,b,c,r,d)
a.eC.set(r,s)
return s},
ia(a,b,c,d,e){var s,r,q,p,o,n,m,l
if(e){s=c.length
r=A.ea(s)
for(q=0,p=0;p<s;++p){o=c[p]
if(o.w===1){r[p]=o;++q}}if(q>0){n=A.aA(a,b,r,0)
m=A.b3(a,c,r,0)
return A.eP(a,n,m,c!==m)}}l=new A.a_(null,null)
l.w=12
l.x=b
l.y=c
l.as=d
return A.ak(a,l)},
fD(a,b,c,d){return{u:a,e:b,r:c,s:[],p:0,n:d}},
fF(a){var s,r,q,p,o,n,m,l=a.r,k=a.s
for(s=l.length,r=0;r<s;){q=l.charCodeAt(r)
if(q>=48&&q<=57)r=A.i2(r+1,q,l,k)
else if((((q|32)>>>0)-97&65535)<26||q===95||q===36||q===124)r=A.fE(a,r,l,k,!1)
else if(q===46)r=A.fE(a,r,l,k,!0)
else{++r
switch(q){case 44:break
case 58:k.push(!1)
break
case 33:k.push(!0)
break
case 59:k.push(A.ay(a.u,a.e,k.pop()))
break
case 94:k.push(A.ic(a.u,k.pop()))
break
case 35:k.push(A.bX(a.u,5,"#"))
break
case 64:k.push(A.bX(a.u,2,"@"))
break
case 126:k.push(A.bX(a.u,3,"~"))
break
case 60:k.push(a.p)
a.p=k.length
break
case 62:A.i4(a,k)
break
case 38:A.i3(a,k)
break
case 63:p=a.u
k.push(A.fL(p,A.ay(p,a.e,k.pop()),a.n))
break
case 47:p=a.u
k.push(A.fK(p,A.ay(p,a.e,k.pop()),a.n))
break
case 40:k.push(-3)
k.push(a.p)
a.p=k.length
break
case 41:A.i1(a,k)
break
case 91:k.push(a.p)
a.p=k.length
break
case 93:o=k.splice(a.p)
A.fG(a.u,a.e,o)
a.p=k.pop()
k.push(o)
k.push(-1)
break
case 123:k.push(a.p)
a.p=k.length
break
case 125:o=k.splice(a.p)
A.i6(a.u,a.e,o)
a.p=k.pop()
k.push(o)
k.push(-2)
break
case 43:n=l.indexOf("(",r)
k.push(l.substring(r,n))
k.push(-4)
k.push(a.p)
a.p=k.length
r=n+1
break
default:throw"Bad character "+q}}}m=k.pop()
return A.ay(a.u,a.e,m)},
i2(a,b,c,d){var s,r,q=b-48
for(s=c.length;a<s;++a){r=c.charCodeAt(a)
if(!(r>=48&&r<=57))break
q=q*10+(r-48)}d.push(q)
return a},
fE(a,b,c,d,e){var s,r,q,p,o,n,m=b+1
for(s=c.length;m<s;++m){r=c.charCodeAt(m)
if(r===46){if(e)break
e=!0}else{if(!((((r|32)>>>0)-97&65535)<26||r===95||r===36||r===124))q=r>=48&&r<=57
else q=!0
if(!q)break}}p=c.substring(b,m)
if(e){s=a.u
o=a.e
if(o.w===9)o=o.x
n=A.ih(s,o.x)[p]
if(n==null)A.ad('No "'+p+'" in "'+A.hO(o)+'"')
d.push(A.bY(s,o,n))}else d.push(p)
return m},
i4(a,b){var s,r=a.u,q=A.fC(a,b),p=b.pop()
if(typeof p=="string")b.push(A.bW(r,p,q))
else{s=A.ay(r,a.e,p)
switch(s.w){case 11:b.push(A.eP(r,s,q,a.n))
break
default:b.push(A.eO(r,s,q))
break}}},
i1(a,b){var s,r,q,p=a.u,o=b.pop(),n=null,m=null
if(typeof o=="number")switch(o){case-1:n=b.pop()
break
case-2:m=b.pop()
break
default:b.push(o)
break}else b.push(o)
s=A.fC(a,b)
o=b.pop()
switch(o){case-3:o=b.pop()
if(n==null)n=p.sEA
if(m==null)m=p.sEA
r=A.ay(p,a.e,o)
q=new A.cL()
q.a=s
q.b=n
q.c=m
b.push(A.fJ(p,r,q))
return
case-4:b.push(A.fM(p,b.pop(),s))
return
default:throw A.b(A.c7("Unexpected state under `()`: "+A.j(o)))}},
i3(a,b){var s=b.pop()
if(0===s){b.push(A.bX(a.u,1,"0&"))
return}if(1===s){b.push(A.bX(a.u,4,"1&"))
return}throw A.b(A.c7("Unexpected extended operation "+A.j(s)))},
fC(a,b){var s=b.splice(a.p)
A.fG(a.u,a.e,s)
a.p=b.pop()
return s},
ay(a,b,c){if(typeof c=="string")return A.bW(a,c,a.sEA)
else if(typeof c=="number"){b.toString
return A.i5(a,b,c)}else return c},
fG(a,b,c){var s,r=c.length
for(s=0;s<r;++s)c[s]=A.ay(a,b,c[s])},
i6(a,b,c){var s,r=c.length
for(s=2;s<r;s+=3)c[s]=A.ay(a,b,c[s])},
i5(a,b,c){var s,r,q=b.w
if(q===9){if(c===0)return b.x
s=b.y
r=s.length
if(c<=r)return s[c-1]
c-=r
b=b.x
q=b.w}else if(c===0)return b
if(q!==8)throw A.b(A.c7("Indexed base must be an interface type"))
s=b.y
if(c<=s.length)return s[c-1]
throw A.b(A.c7("Bad index "+c+" for "+b.i(0)))},
jl(a,b,c){var s,r=b.d
if(r==null)r=b.d=new Map()
s=r.get(c)
if(s==null){s=A.v(a,b,null,c,null)
r.set(c,s)}return s},
v(a,b,c,d,e){var s,r,q,p,o,n,m,l,k,j,i
if(b===d)return!0
if(A.aB(d))return!0
s=b.w
if(s===4)return!0
if(A.aB(b))return!1
if(b.w===1)return!0
r=s===13
if(r)if(A.v(a,c[b.x],c,d,e))return!0
q=d.w
p=t.P
if(b===p||b===t.T){if(q===7)return A.v(a,b,c,d.x,e)
return d===p||d===t.T||q===6}if(d===t.K){if(s===7)return A.v(a,b.x,c,d,e)
return s!==6}if(s===7){if(!A.v(a,b.x,c,d,e))return!1
return A.v(a,A.eJ(a,b),c,d,e)}if(s===6)return A.v(a,p,c,d,e)&&A.v(a,b.x,c,d,e)
if(q===7){if(A.v(a,b,c,d.x,e))return!0
return A.v(a,b,c,A.eJ(a,d),e)}if(q===6)return A.v(a,b,c,p,e)||A.v(a,b,c,d.x,e)
if(r)return!1
p=s!==11
if((!p||s===12)&&d===t.Z)return!0
o=s===10
if(o&&d===t.L)return!0
if(q===12){if(b===t.g)return!0
if(s!==12)return!1
n=b.y
m=d.y
l=n.length
if(l!==m.length)return!1
c=c==null?n:n.concat(c)
e=e==null?m:m.concat(e)
for(k=0;k<l;++k){j=n[k]
i=m[k]
if(!A.v(a,j,c,i,e)||!A.v(a,i,e,j,c))return!1}return A.fX(a,b.x,c,d.x,e)}if(q===11){if(b===t.g)return!0
if(p)return!1
return A.fX(a,b,c,d,e)}if(s===8){if(q!==8)return!1
return A.iC(a,b,c,d,e)}if(o&&q===10)return A.iH(a,b,c,d,e)
return!1},
fX(a3,a4,a5,a6,a7){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2
if(!A.v(a3,a4.x,a5,a6.x,a7))return!1
s=a4.y
r=a6.y
q=s.a
p=r.a
o=q.length
n=p.length
if(o>n)return!1
m=n-o
l=s.b
k=r.b
j=l.length
i=k.length
if(o+j<n+i)return!1
for(h=0;h<o;++h){g=q[h]
if(!A.v(a3,p[h],a7,g,a5))return!1}for(h=0;h<m;++h){g=l[h]
if(!A.v(a3,p[o+h],a7,g,a5))return!1}for(h=0;h<i;++h){g=l[m+h]
if(!A.v(a3,k[h],a7,g,a5))return!1}f=s.c
e=r.c
d=f.length
c=e.length
for(b=0,a=0;a<c;a+=3){a0=e[a]
for(;;){if(b>=d)return!1
a1=f[b]
b+=3
if(a0<a1)return!1
a2=f[b-2]
if(a1<a0){if(a2)return!1
continue}g=e[a+1]
if(a2&&!g)return!1
g=f[b-1]
if(!A.v(a3,e[a+2],a7,g,a5))return!1
break}}while(b<d){if(f[b+1])return!1
b+=3}return!0},
iC(a,b,c,d,e){var s,r,q,p,o,n=b.x,m=d.x
while(n!==m){s=a.tR[n]
if(s==null)return!1
if(typeof s=="string"){n=s
continue}r=s[m]
if(r==null)return!1
q=r.length
p=q>0?new Array(q):v.typeUniverse.sEA
for(o=0;o<q;++o)p[o]=A.bY(a,b,r[o])
return A.fP(a,p,null,c,d.y,e)}return A.fP(a,b.y,null,c,d.y,e)},
fP(a,b,c,d,e,f){var s,r=b.length
for(s=0;s<r;++s)if(!A.v(a,b[s],d,e[s],f))return!1
return!0},
iH(a,b,c,d,e){var s,r=b.y,q=d.y,p=r.length
if(p!==q.length)return!1
if(b.x!==d.x)return!1
for(s=0;s<p;++s)if(!A.v(a,r[s],c,q[s],e))return!1
return!0},
b6(a){var s=a.w,r=!0
if(!(a===t.P||a===t.T))if(!A.aB(a))if(s!==6)r=s===7&&A.b6(a.x)
return r},
aB(a){var s=a.w
return s===2||s===3||s===4||s===5||a===t.X},
fO(a,b){var s,r,q=Object.keys(b),p=q.length
for(s=0;s<p;++s){r=q[s]
a[r]=b[r]}},
ea(a){return a>0?new Array(a):v.typeUniverse.sEA},
a_:function a_(a,b){var _=this
_.a=a
_.b=b
_.r=_.f=_.d=_.c=null
_.w=0
_.as=_.Q=_.z=_.y=_.x=null},
cL:function cL(){this.c=this.b=this.a=null},
e7:function e7(a){this.a=a},
cK:function cK(){},
bU:function bU(a){this.a=a},
hU(){var s,r,q
if(self.scheduleImmediate!=null)return A.j_()
if(self.MutationObserver!=null&&self.document!=null){s={}
r=self.document.createElement("div")
q=self.document.createElement("span")
s.a=null
new self.MutationObserver(A.c4(new A.dC(s),1)).observe(r,{childList:true})
return new A.dB(s,r,q)}else if(self.setImmediate!=null)return A.j0()
return A.j1()},
hV(a){self.scheduleImmediate(A.c4(new A.dD(t.M.a(a)),0))},
hW(a){self.setImmediate(A.c4(new A.dE(t.M.a(a)),0))},
hX(a){A.eK(B.Q,t.M.a(a))},
eK(a,b){return A.i7(a.a/1000|0,b)},
i7(a,b){var s=new A.e5()
s.bb(a,b)
return s},
X(a){return new A.bF(new A.e($.f,a.h("e<0>")),a.h("bF<0>"))},
W(a,b){a.$2(0,null)
b.b=!0
return b.a},
B(a,b){A.il(a,b)},
V(a,b){b.a_(a)},
U(a,b){b.am(A.H(a),A.I(a))},
il(a,b){var s,r,q=new A.eg(b),p=new A.eh(b)
if(a instanceof A.e)a.aT(q,p,t.z)
else{s=t.z
if(a instanceof A.e)a.P(q,p,s)
else{r=new A.e($.f,t._)
r.a=8
r.c=a
r.aT(q,p,s)}}},
Y(a){var s=function(b,c){return function(d,e){while(true){try{b(d,e)
break}catch(r){e=r
d=c}}}}(a,1)
return $.f.ap(new A.em(s),t.H,t.S,t.z)},
fI(a,b,c){return 0},
c8(a){var s
if(t.C.b(a)){s=a.gJ()
if(s!=null)return s}return B.e},
hG(a,b){var s,r,q,p,o,n,m,l=null
try{l=a.$0()}catch(q){s=A.H(q)
r=A.I(q)
p=new A.e($.f,b.h("e<0>"))
o=s
n=r
m=A.fW(o,n)
o=new A.x(o,n==null?A.c8(o):n)
p.L(o)
return p}return b.h("A<0>").b(l)?l:A.dI(l,b)},
fW(a,b){if($.f===B.b)return null
return null},
iz(a,b){if($.f!==B.b)A.fW(a,b)
if(b==null)if(t.C.b(a)){b=a.gJ()
if(b==null){A.fs(a,B.e)
b=B.e}}else b=B.e
else if(t.C.b(a))A.fs(a,b)
return new A.x(a,b)},
dI(a,b){var s=new A.e($.f,b.h("e<0>"))
b.a(a)
s.a=8
s.c=a
return s},
dM(a,b,c){var s,r,q,p,o={},n=o.a=a
for(s=t._;r=n.a,(r&4)!==0;n=a){a=s.a(n.c)
o.a=a}if(n===b){s=A.hP()
b.L(new A.x(new A.a4(!0,n,null,"Cannot complete a future with itself"),s))
return}q=b.a&1
s=n.a=r|q
if((s&24)===0){p=t.F.a(b.c)
b.a=b.a&1|4
b.c=n
n.aP(p)
return}if(!c)if(b.c==null)n=(s&16)===0||q!==0
else n=!1
else n=!0
if(n){p=b.N()
b.U(o.a)
A.ax(b,p)
return}b.a^=2
A.b2(null,null,b.b,t.M.a(new A.dN(o,b)))},
ax(a,b){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d={},c=d.a=a
for(s=t.n,r=t.F;;){q={}
p=c.a
o=(p&16)===0
n=!o
if(b==null){if(n&&(p&1)===0){m=s.a(c.c)
A.cU(m.a,m.b)}return}q.a=b
l=b.a
for(c=b;l!=null;c=l,l=k){c.a=null
A.ax(d.a,c)
q.a=l
k=l.a}p=d.a
j=p.c
q.b=n
q.c=j
if(o){i=c.c
i=(i&1)!==0||(i&15)===8}else i=!0
if(i){h=c.b.b
if(n){p=p.b===h
p=!(p||p)}else p=!1
if(p){s.a(j)
A.cU(j.a,j.b)
return}g=$.f
if(g!==h)$.f=h
else g=null
c=c.c
if((c&15)===8)new A.dR(q,d,n).$0()
else if(o){if((c&1)!==0)new A.dQ(q,j).$0()}else if((c&2)!==0)new A.dP(d,q).$0()
if(g!=null)$.f=g
c=q.c
if(c instanceof A.e){p=q.a.$ti
p=p.h("A<2>").b(c)||!p.y[1].b(c)}else p=!1
if(p){f=q.a.b
if((c.a&24)!==0){e=r.a(f.c)
f.c=null
b=f.V(e)
f.a=c.a&30|f.a&1
f.c=c.c
d.a=c
continue}else A.dM(c,f,!0)
return}}f=q.a.b
e=r.a(f.c)
f.c=null
b=f.V(e)
c=q.b
p=q.c
if(!c){f.$ti.c.a(p)
f.a=8
f.c=p}else{s.a(p)
f.a=f.a&1|16
f.c=p}d.a=f
c=f}},
iP(a,b){var s
if(t.Q.b(a))return b.ap(a,t.z,t.K,t.l)
s=t.v
if(s.b(a))return s.a(a)
throw A.b(A.aE(a,"onError",u.c))},
iM(){var s,r
for(s=$.b1;s!=null;s=$.b1){$.c2=null
r=s.b
$.b1=r
if(r==null)$.c1=null
s.a.$0()}},
iU(){$.eV=!0
try{A.iM()}finally{$.c2=null
$.eV=!1
if($.b1!=null)$.f8().$1(A.h6())}},
h3(a){var s=new A.cG(a),r=$.c1
if(r==null){$.b1=$.c1=s
if(!$.eV)$.f8().$1(A.h6())}else $.c1=r.b=s},
iR(a){var s,r,q,p=$.b1
if(p==null){A.h3(a)
$.c2=$.c1
return}s=new A.cG(a)
r=$.c2
if(r==null){s.b=p
$.b1=$.c2=s}else{q=r.b
s.b=q
$.c2=r.b=s
if(q==null)$.c1=s}},
jr(a){var s=null,r=$.f
if(B.b===r){A.b2(s,s,B.b,a)
return}A.b2(s,s,r,t.M.a(r.aj(a)))},
jA(a,b){A.f_(a,"stream",t.K)
return new A.cN(b.h("cN<0>"))},
fw(a){var s=null
return new A.aX(s,s,s,s,a.h("aX<0>"))},
eX(a){return},
hY(a,b){if(b==null)b=A.j2()
if(t.da.b(b))return a.ap(b,t.z,t.K,t.l)
if(t.d5.b(b))return t.v.a(b)
throw A.b(A.c5("handleError callback must take either an Object (the error), or both an Object (the error) and a StackTrace.",null))},
iN(a,b){A.cU(A.T(a),t.l.a(b))},
hR(a,b){var s=$.f
if(s===B.b)return A.eK(a,t.M.a(b))
return A.eK(a,t.M.a(s.aj(b)))},
cU(a,b){A.iR(new A.ej(a,b))},
h0(a,b,c,d,e){var s,r=$.f
if(r===c)return d.$0()
$.f=c
s=r
try{r=d.$0()
return r}finally{$.f=s}},
h1(a,b,c,d,e,f,g){var s,r=$.f
if(r===c)return d.$1(e)
$.f=c
s=r
try{r=d.$1(e)
return r}finally{$.f=s}},
iQ(a,b,c,d,e,f,g,h,i){var s,r=$.f
if(r===c)return d.$2(e,f)
$.f=c
s=r
try{r=d.$2(e,f)
return r}finally{$.f=s}},
b2(a,b,c,d){t.M.a(d)
if(B.b!==c){d=c.aj(d)
d=d}A.h3(d)},
dC:function dC(a){this.a=a},
dB:function dB(a,b,c){this.a=a
this.b=b
this.c=c},
dD:function dD(a){this.a=a},
dE:function dE(a){this.a=a},
e5:function e5(){this.b=null},
e6:function e6(a,b){this.a=a
this.b=b},
bF:function bF(a,b){this.a=a
this.b=!1
this.$ti=b},
eg:function eg(a){this.a=a},
eh:function eh(a){this.a=a},
em:function em(a){this.a=a},
bT:function bT(a,b){var _=this
_.a=a
_.e=_.d=_.c=_.b=null
_.$ti=b},
b0:function b0(a,b){this.a=a
this.$ti=b},
x:function x(a,b){this.a=a
this.b=b},
bH:function bH(){},
a6:function a6(a,b){this.a=a
this.$ti=b},
ab:function ab(a,b,c,d,e){var _=this
_.a=null
_.b=a
_.c=b
_.d=c
_.e=d
_.$ti=e},
e:function e(a,b){var _=this
_.a=0
_.b=a
_.c=null
_.$ti=b},
dJ:function dJ(a,b){this.a=a
this.b=b},
dO:function dO(a,b){this.a=a
this.b=b},
dN:function dN(a,b){this.a=a
this.b=b},
dL:function dL(a,b){this.a=a
this.b=b},
dK:function dK(a,b){this.a=a
this.b=b},
dR:function dR(a,b,c){this.a=a
this.b=b
this.c=c},
dS:function dS(a,b){this.a=a
this.b=b},
dT:function dT(a){this.a=a},
dQ:function dQ(a,b){this.a=a
this.b=b},
dP:function dP(a,b){this.a=a
this.b=b},
dU:function dU(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
dV:function dV(a,b,c){this.a=a
this.b=b
this.c=c},
dW:function dW(a,b){this.a=a
this.b=b},
cG:function cG(a){this.a=a
this.b=null},
bA:function bA(){},
dk:function dk(a,b){this.a=a
this.b=b},
dl:function dl(a,b){this.a=a
this.b=b},
bQ:function bQ(){},
e4:function e4(a){this.a=a},
e3:function e3(a){this.a=a},
cH:function cH(){},
aX:function aX(a,b,c,d,e){var _=this
_.a=null
_.b=0
_.c=null
_.d=a
_.e=b
_.f=c
_.r=d
_.$ti=e},
aY:function aY(a,b){this.a=a
this.$ti=b},
aZ:function aZ(a,b,c,d,e,f){var _=this
_.w=a
_.a=b
_.c=c
_.d=d
_.e=e
_.r=_.f=null
_.$ti=f},
bG:function bG(){},
dF:function dF(a){this.a=a},
bS:function bS(){},
aj:function aj(){},
av:function av(a,b){this.b=a
this.a=null
this.$ti=b},
cI:function cI(){},
a1:function a1(a){var _=this
_.a=0
_.c=_.b=null
_.$ti=a},
e0:function e0(a,b){this.a=a
this.b=b},
cN:function cN(a){this.$ti=a},
c_:function c_(){},
cM:function cM(){},
e2:function e2(a,b){this.a=a
this.b=b},
ej:function ej(a,b){this.a=a
this.b=b},
db(a,b,c){return b.h("@<0>").t(c).h("fm<1,2>").a(A.jd(a,new A.ap(b.h("@<0>").t(c).h("ap<1,2>"))))},
eG(a,b){return new A.ap(a.h("@<0>").t(b).h("ap<1,2>"))},
eH(a){var s,r
if(A.f4(a))return"{...}"
s=new A.aW("")
try{r={}
B.a.j($.O,a)
s.a+="{"
r.a=!0
a.I(0,new A.de(r,s))
s.a+="}"}finally{if(0>=$.O.length)return A.h($.O,-1)
$.O.pop()}r=s.a
return r.charCodeAt(0)==0?r:r},
r:function r(){},
bp:function bp(){},
dd:function dd(a){this.a=a},
de:function de(a,b){this.a=a
this.b=b},
fl(a,b,c){return new A.bk(a,b)},
iq(a){return a.b6()},
i_(a,b){return new A.dY(a,[],A.j7())},
i0(a,b,c){var s,r=new A.aW(""),q=A.i_(r,b)
q.a3(a)
s=r.a
return s.charCodeAt(0)==0?s:s},
cb:function cb(){},
cf:function cf(){},
bk:function bk(a,b){this.a=a
this.b=b},
cq:function cq(a,b){this.a=a
this.b=b},
cp:function cp(){},
d9:function d9(a){this.b=a},
dZ:function dZ(){},
e_:function e_(a,b){this.a=a
this.b=b},
dY:function dY(a,b,c){this.c=a
this.a=b
this.b=c},
dt:function dt(){},
e9:function e9(a){this.b=0
this.c=a},
hE(a,b){a=A.w(a,new Error())
if(a==null)a=A.T(a)
a.stack=b.i(0)
throw a},
hJ(a,b,c){var s,r
if(a>4294967295)A.ad(A.bx(a,0,4294967295,"length",null))
s=A.z(new Array(a),c.h("p<0>"))
s.$flags=1
r=s
return r},
dc(a,b,c){var s,r,q=A.z([],c.h("p<0>"))
for(s=a.length,r=0;r<a.length;a.length===s||(0,A.an)(a),++r)B.a.j(q,c.a(a[r]))
if(b)return q
q.$flags=1
return q},
fn(a,b){var s,r
if(Array.isArray(a))return A.z(a.slice(0),b.h("p<0>"))
s=A.z([],b.h("p<0>"))
for(r=J.eC(a);r.n();)B.a.j(s,r.gq())
return s},
fx(a,b,c){var s=J.eC(b)
if(!s.n())return a
if(c.length===0){do a+=A.j(s.gq())
while(s.n())}else{a+=A.j(s.gq())
while(s.n())a=a+c+A.j(s.gq())}return a},
hP(){return A.I(new Error())},
fi(a,b,c){var s,r,q
for(s=a.length,r=0;r<s;++r){q=a[r]
if(q.b===b)return q}throw A.b(A.aE(b,"name","No enum value with that name"))},
ch(a){if(typeof a=="number"||A.cT(a)||a==null)return J.aD(a)
if(typeof a=="string")return JSON.stringify(a)
return A.fr(a)},
hF(a,b){A.f_(a,"error",t.K)
A.f_(b,"stackTrace",t.l)
A.hE(a,b)},
c7(a){return new A.c6(a)},
c5(a,b){return new A.a4(!1,null,b,a)},
aE(a,b,c){return new A.a4(!0,a,b,c)},
ft(a,b){return new A.bw(null,null,!0,a,b,"Value not in range")},
bx(a,b,c,d,e){return new A.bw(b,c,!0,a,d,"Invalid value")},
eI(a,b,c){if(0>a||a>c)throw A.b(A.bx(a,0,c,"start",null))
if(b!=null){if(a>b||b>c)throw A.b(A.bx(b,a,c,"end",null))
return b}return c},
hN(a,b){return a},
fj(a,b,c,d){return new A.cj(b,!0,a,d,"Index out of range")},
bE(a){return new A.bD(a)},
fz(a){return new A.cA(a)},
a8(a){return new A.au(a)},
ce(a){return new A.cd(a)},
eD(a){return new A.ci(a)},
hH(a,b,c){var s,r
if(A.f4(a)){if(b==="("&&c===")")return"(...)"
return b+"..."+c}s=A.z([],t.s)
B.a.j($.O,a)
try{A.iL(a,s)}finally{if(0>=$.O.length)return A.h($.O,-1)
$.O.pop()}r=A.fx(b,t.hf.a(s),", ")+c
return r.charCodeAt(0)==0?r:r},
fk(a,b,c){var s,r
if(A.f4(a))return b+"..."+c
s=new A.aW(b)
B.a.j($.O,a)
try{r=s
r.a=A.fx(r.a,a,", ")}finally{if(0>=$.O.length)return A.h($.O,-1)
$.O.pop()}s.a+=c
r=s.a
return r.charCodeAt(0)==0?r:r},
iL(a,b){var s,r,q,p,o,n,m,l=a.gu(a),k=0,j=0
for(;;){if(!(k<80||j<3))break
if(!l.n())return
s=A.j(l.gq())
B.a.j(b,s)
k+=s.length+2;++j}if(!l.n()){if(j<=5)return
if(0>=b.length)return A.h(b,-1)
r=b.pop()
if(0>=b.length)return A.h(b,-1)
q=b.pop()}else{p=l.gq();++j
if(!l.n()){if(j<=4){B.a.j(b,A.j(p))
return}r=A.j(p)
if(0>=b.length)return A.h(b,-1)
q=b.pop()
k+=r.length+2}else{o=l.gq();++j
for(;l.n();p=o,o=n){n=l.gq();++j
if(j>100){for(;;){if(!(k>75&&j>3))break
if(0>=b.length)return A.h(b,-1)
k-=b.pop().length+2;--j}B.a.j(b,"...")
return}}q=A.j(p)
r=A.j(o)
k+=r.length+q.length+4}}if(j>b.length+2){k+=5
m="..."}else m=null
for(;;){if(!(k>80&&b.length>3))break
if(0>=b.length)return A.h(b,-1)
k-=b.pop().length+2
if(m==null){k+=5
m="..."}}if(m!=null)B.a.j(b,m)
B.a.j(b,q)
B.a.j(b,r)},
fo(a,b,c,d,e){var s
if(B.d===c){s=B.c.gl(a)
b=J.P(b)
return A.dm(A.M(A.M($.cX(),s),b))}if(B.d===d){s=B.c.gl(a)
b=J.P(b)
c=J.P(c)
return A.dm(A.M(A.M(A.M($.cX(),s),b),c))}if(B.d===e){s=B.c.gl(a)
b=J.P(b)
c=J.P(c)
d=J.P(d)
return A.dm(A.M(A.M(A.M(A.M($.cX(),s),b),c),d))}s=B.c.gl(a)
b=J.P(b)
c=J.P(c)
d=J.P(d)
e=J.P(e)
e=A.dm(A.M(A.M(A.M(A.M(A.M($.cX(),s),b),c),d),e))
return e},
bc:function bc(a){this.a=a},
cJ:function cJ(){},
n:function n(){},
c6:function c6(a){this.a=a},
a9:function a9(){},
a4:function a4(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
bw:function bw(a,b,c,d,e,f){var _=this
_.e=a
_.f=b
_.a=c
_.b=d
_.c=e
_.d=f},
cj:function cj(a,b,c,d,e){var _=this
_.f=a
_.a=b
_.b=c
_.c=d
_.d=e},
bD:function bD(a){this.a=a},
cA:function cA(a){this.a=a},
au:function au(a){this.a=a},
cd:function cd(a){this.a=a},
cr:function cr(){},
bz:function bz(){},
dH:function dH(a){this.a=a},
ci:function ci(a){this.a=a},
d:function d(){},
E:function E(a,b,c){this.a=a
this.b=b
this.$ti=c},
t:function t(){},
c:function c(){},
cO:function cO(){},
aW:function aW(a){this.a=a},
hI(a,b){var s,r,q,p,o
if(b.length===0)return!1
s=b.split(".")
r=v.G
for(q=s.length,p=0;p<q;++p,r=o){o=r[s[p]]
A.eR(o)
if(o==null)return!1}return a instanceof t.g.a(r)},
dg:function dg(a){this.a=a},
cS(a){var s
if(typeof a=="function")throw A.b(A.c5("Attempting to rewrap a JS function.",null))
s=function(b,c){return function(d){return b(c,d,arguments.length)}}(A.im,a)
s[$.f7()]=a
return s},
im(a,b,c){t.Z.a(a)
if(A.F(c)>=1)return a.$1(b)
return a.$0()},
he(a,b){var s=new A.e($.f,b.h("e<0>")),r=new A.a6(s,b.h("a6<0>"))
a.then(A.c4(new A.ew(r,b),1),A.c4(new A.ex(r),1))
return s},
ew:function ew(a,b){this.a=a
this.b=b},
ex:function ex(a){this.a=a},
j3(a,b){var s,r="codecString"
if(b.a0(r)){s=b.m(0,r)
s.toString
return s}A:{if(B.n===a){s="mp4a.40.2"
break A}if(B.o===a){s="opus"
break A}if(B.q===a){s="mp3"
break A}if(B.r===a){s="flac"
break A}if(B.p===a){s="vorbis"
break A}s=A.ad(A.bE("WebCodecs audio: no codec string for "+a.i(0)))}return s},
eL(a){var s=0,r=A.X(t.g0),q,p,o,n,m,l,k
var $async$eL=A.Y(function(b,c){if(b===1)return A.U(c,r)
for(;;)switch(s){case 0:l=a.c
k=a.d
if(l==null||k==null)throw A.b(A.fg("webcodecs","WebCodecs audio decode requires sampleRate + channels in AudioDecoderConfig (WebCodecs does not derive them from the bitstream). Got sampleRate="+A.j(l)+" channels="+A.j(k)+"."))
p=new A.cC(A.z([],t.A))
o=A.j3(a.a,a.e)
p.a=A.G(new v.G.AudioDecoder({output:A.cS(new A.dv(p)),error:A.cS(new A.dw(p))}))
n=a.b
m=n!=null&&n.length!==0?{codec:o,sampleRate:l,numberOfChannels:k,description:new Uint8Array(A.fT(n))}:{codec:o,sampleRate:l,numberOfChannels:k}
p.a.configure(m)
p.X()
q=p
s=1
break
case 1:return A.V(q,r)}})
return A.W($async$eL,r)},
cC:function cC(a){var _=this
_.a=null
_.b=a
_.d=_.c=null},
du:function du(){},
dv:function dv(a){this.a=a},
dw:function dw(a){this.a=a},
jv(a,b){var s,r="codecString"
if(b.a0(r)){s=b.m(0,r)
s.toString
return s}A:{if(B.y===a){s="avc1.42E01E"
break A}if(B.z===a){s="hev1.1.6.L93.B0"
break A}if(B.C===a){s="vp8"
break A}if(B.B===a){s="vp09.00.10.08"
break A}if(B.A===a){s="av01.0.04M.08"
break A}s=A.ad(A.bE("WebCodecs: no default codec string for "+a.i(0)+". Supply one via backendOptions['codecString']."))}return s},
eM(a){var s=0,r=A.X(t.dD),q,p,o,n,m
var $async$eM=A.Y(function(b,c){if(b===1)return A.U(c,r)
for(;;)switch(s){case 0:n=new A.cD(A.z([],t.t))
m=A.jv(a.a,a.x)
n.a=A.G(new v.G.VideoDecoder({output:A.cS(new A.dy(n)),error:A.cS(new A.dz(n))}))
p=a.c
o=p!=null&&p.length!==0?{codec:m,description:new Uint8Array(A.fT(p))}:{codec:m}
n.a.configure(o)
n.Z()
q=n
s=1
break
case 1:return A.V(q,r)}})
return A.W($async$eM,r)},
cD:function cD(a){var _=this
_.a=null
_.b=a
_.d=_.c=null},
dx:function dx(){},
dy:function dy(a){this.a=a},
dz:function dz(a){this.a=a},
cE:function cE(a){this.a=a
this.b=!1},
c3(a){return A.j4(a)},
j4(a){var s=0,r=A.X(t.H),q=1,p=[],o,n,m,l,k,j
var $async$c3=A.Y(function(b,c){if(b===1){p.push(c)
s=q}for(;;)switch(s){case 0:l={}
k=a.r
k.toString
t.I.a(k)
o=A.ef(k.m(0,"role"))
l.a=l.b=null
a.bF(new A.en(l,o,k))
s=2
return A.B(a.c.a,$async$c3)
case 2:q=4
k=l.b
k=k==null?null:k.v()
n=t.H
s=7
return A.B(k instanceof A.e?k:A.dI(k,n),$async$c3)
case 7:l=l.a
l=l==null?null:l.v()
s=8
return A.B(l instanceof A.e?l:A.dI(l,n),$async$c3)
case 8:q=1
s=6
break
case 4:q=3
j=p.pop()
s=6
break
case 3:s=1
break
case 6:return A.V(null,r)
case 1:return A.U(p.at(-1),r)}})
return A.W($async$c3,r)},
h4(a){var s
if(a==null)return null
s=a.b?null:a.a
if(s==null){a.v()
throw A.b(B.P)}return new A.aV(s)},
h_(a){var s,r,q,p=a.m(0,"options")
if(!t.I.b(p))return B.a0
s=t.N
s=A.eG(s,s)
for(r=p.ga2(),r=r.gu(r);r.n();){q=r.gq()
s.E(0,q.a,A.j(q.b))}return s},
jn(){A.jq(A.j5())
return null},
en:function en(a,b,c){this.a=a
this.b=b
this.c=c},
N:function N(a,b){this.a=a
this.b=b},
Q:function Q(a,b){this.a=a
this.b=b},
d1:function d1(a,b,c){this.a=a
this.c=b
this.x=c},
cY:function cY(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e},
fg(a,b){return new A.d_(a,b)},
fh(a,b){return new A.cc(a,b)},
df:function df(){},
d_:function d_(a,b){this.b=a
this.a=b},
cc:function cc(a,b){this.b=a
this.a=b},
d2:function d2(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.e=d},
aG:function aG(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e},
jq(a){var s={}
s.a=null
A.G(v.G.self).onmessage=A.cS(new A.ez(s,a))},
ip(a){var s,r,q,p,o,n,m,l,k,j,i,h=null
if(a!=null){q=A.hI(a,"Object")
q=!q}else q=!0
if(q)return h
A.G(a)
s=t.dE.a(a.h)
if(s==null)return h
r=null
try{q=s
p=q.byteLength
if(p<12)A.ad(A.eD("spawn envelope: need at least 12 bytes, got "+p))
o=A.fe(q,0,12)
n=o.getUint8(0)
if(n!==1)A.ad(A.eD("spawn envelope: unsupported version "+n+" (expected 1)"))
m=o.getUint8(1)
l=A.hS(m)
if(l==null)A.ad(A.eD("spawn envelope: unknown kind "+m))
r=new A.cF(n,l,o.getUint16(2,!0),o.getUint32(4,!0),o.getUint32(8,!0))}catch(k){if(A.H(k) instanceof A.ci)return h
else throw k}j=a.p
if(j==null)i=h
else i=r.c!==0||r.b===B.l||r.b===B.m||r.b===B.h?t.Y.a(j):A.eT(j)
return new A.J(r.b,r.c,r.d,i)},
iX(a,b){var s,r,q=t.c.a(new v.G.Array()),p=new A.el(A.z([],t.f),q)
for(s=b.length,r=0;r<b.length;b.length===s||(0,A.an)(b),++r)p.$1(b[r])
return q},
eZ(a,b){var s,r,q,p
if(a==null)return null
if(a instanceof A.aV){s={}
r=a.a
s.$spawn$platform=r
if(r!=null&&A.fS(r)!=="SharedArrayBuffer")B.a.j(b,r)
return s}if(A.cT(a))return a
if(A.eW(a))return a
if(typeof a=="number")return a
if(typeof a=="string")return a
if(t.J.b(a))return t.a.a(a)
if(t.p.b(a))return a
if(t.U.b(a))return a
if(t.go.b(a))return a
if(t.dQ.b(a))return a
if(t.h7.b(a))return a
if(t.an.b(a))return a
if(t.bv.b(a))return a
if(t.h4.b(a))return a
if(t.q.b(a))return a
if(t.V.b(a))return a
if(t.j.b(a)){q=t.c.a(new v.G.Array())
for(p=0;p<a.length;++p)q[p]=A.eZ(a[p],b)
return q}if(t.G.b(a)){s={}
a.I(0,new A.ek(s,b))
return s}throw A.b(A.aE(a,"message","spawn cannot carry this value"))},
eT(a){var s,r,q,p
if(a==null)return null
if(typeof a==="boolean")return A.eQ(a)
if(typeof a==="string")return A.a2(a)
if(typeof a==="number"){A.ee(a)
if(isFinite(a))s=a===(a<0?Math.ceil(a):Math.floor(a))
else s=!1
if(s)return B.j.b5(a)
return a}if(!(typeof a==="object"))return null
switch(A.fS(a)){case"ArrayBuffer":return t.a.a(a)
case"Uint8Array":return t.Y.a(a)
case"Int8Array":return t.cv.a(a)
case"Uint8ClampedArray":return t.gi.a(a)
case"Int16Array":return t.at.a(a)
case"Uint16Array":return t.d.a(a)
case"Int32Array":return t.ha.a(a)
case"Uint32Array":return t.dk.a(a)
case"Float32Array":return t.al.a(a)
case"Float64Array":return t.c2.a(a)
case"DataView":return t.gT.a(a)
case"Array":t.c.a(a)
r=A.F(A.ee(a.length))
s=[]
for(q=0;q<r;++q)s.push(A.eT(a[q]))
return s
default:A.G(a)
if("$spawn$platform" in a)return new A.aV(a.$spawn$platform)
p=t.c.a(v.G.Object.keys(a))
r=A.F(A.ee(p.length))
s=A.eG(t.N,t.X)
for(q=0;q<r;++q)s.E(0,A.a2(p[q]),A.eT(a[A.a2(p[q])]))
return s}},
fS(a){var s,r=A.eR(A.G(a).constructor)
if(r==null)s=null
else{s=A.ef(r.name)
if(s==null)s=null}return s},
ez:function ez(a,b){this.a=a
this.b=b},
ey:function ey(){},
cQ:function cQ(a,b){this.a=a
this.b=b},
el:function el(a,b){this.a=a
this.b=b},
ek:function ek(a,b){this.a=a
this.b=b},
cv:function cv(a,b){this.a=a
this.b=b},
cw:function cw(a,b){this.a=a
this.b=b},
dj:function dj(){},
cW(a,b,c,d){return A.jp(a,b,c,d)},
jp(a,b,c,a0){var s=0,r=A.X(t.H),q=1,p=[],o=[],n,m,l,k,j,i,h,g,f,e,d
var $async$cW=A.Y(function(a1,a2){if(a1===1){p.push(a2)
s=q}for(;;)switch(s){case 0:f=t.X
e=new A.bZ(a,A.fw(f),new A.a6(new A.e($.f,t.D),t.h),A.z([],t.b4),c)
a.G(new A.J(B.l,0,0,B.i.a1(B.M.bB(A.db(["v",1,"caps",a0.b6()],t.N,f),null))))
f=a.a
n=new A.aY(f,A.o(f).h("aY<1>")).bI(e.gbm(),e.gbo())
q=3
f=b.$1(e)
s=6
return A.B(f instanceof A.e?f:A.dI(f,t.H),$async$cW)
case 6:o.push(5)
s=4
break
case 3:q=2
d=p.pop()
m=A.H(d)
l=A.I(d)
f=A.T(m)
j=t.l.a(l)
i=e.a
h=J.ac(f)
g=A.C(h.gk(f).a,null)
f=h.i(f)
j=j.i(0)
i.G(new A.J(B.h,0,0,B.i.a1(g+"\n"+A.f6(f,"\n"," ")+"\n"+j)))
o.push(5)
s=4
break
case 2:o=[1]
case 4:q=1
e.ab()
f=n
if(((f.e&=4294967279)&8)===0)f.aC()
f=f.f
s=7
return A.B(f==null?$.eA():f,$async$cW)
case 7:a.G(B.R)
s=o.pop()
break
case 5:return A.V(null,r)
case 1:return A.U(p.at(-1),r)}})
return A.W($async$cW,r)},
bZ:function bZ(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=null
_.f=!1
_.r=e},
eb:function eb(a,b){this.a=a
this.b=b},
ec:function ec(a,b){this.a=a
this.b=b},
ed:function ed(a,b){this.a=a
this.b=b},
J:function J(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
ja(a){A.eS(a,A.z([],t.f),"message")
return new A.bO(0,a)},
f2(a,b){if(a===0)return b
if(!t.p.b(b))throw A.b(A.a8("spawn: frame declares typeId "+a+" but carries "+J.b7(b).i(0)+" instead of bytes"))
return $.hs().bz(a,b)},
eS(a,b,c){var s,r,q,p
if(a==null||A.cT(a)||typeof a=="number"||typeof a=="string"||t.ak.b(a)||t.J.b(a)||a instanceof A.aV)return
s=t.j.b(a)
if(s||t.G.b(a)){for(r=b.length,q=0;q<r;++q)if(b[q]===a)throw A.b(A.aE(a,c,"spawn cannot carry a cyclic structure"))
B.a.j(b,a)
if(s)for(s=c+"[",p=0;p<a.length;++p)A.eS(a[p],b,s+p+"]")
else if(t.G.b(a))a.I(0,new A.ei(c,b))
if(0>=b.length)return A.h(b,-1)
b.pop()
return}throw A.b(A.aE(a,c,"spawn cannot carry "+J.b7(a).i(0)+". Wrap a platform object (VideoFrame, AudioData, ImageBitmap, ...) in a PlatformValue. Portable values are null, bool, int, double, String, TypedData, ByteBuffer, and List/Map<String, ...> of those. Implement WireMessage for anything else."))},
ei:function ei(a,b){this.a=a
this.b=b},
aV:function aV(a){this.a=a},
hS(a){var s,r
for(s=0;s<6;++s){r=B.W[s]
if(r.c===a)return r}return null},
a5:function a5(a,b,c){this.c=a
this.a=b
this.b=c},
cF:function cF(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e},
dA:function dA(a){this.a=a},
fe(a,b,c){var s=a.BYTES_PER_ELEMENT
c=A.eI(b,c,B.c.av(a.byteLength,s))
return J.hv(B.a1.gby(a),a.byteOffset+b*s,(c-b)*s)}},B={}
var w=[A,J,B]
var $={}
A.eE.prototype={}
J.ck.prototype={
D(a,b){return a===b},
gl(a){return A.bv(a)},
i(a){return"Instance of '"+A.ct(a)+"'"},
gk(a){return A.a3(A.eU(this))}}
J.cm.prototype={
i(a){return String(a)},
gl(a){return a?519018:218159},
gk(a){return A.a3(t.y)},
$ik:1,
$icV:1}
J.bh.prototype={
D(a,b){return null==b},
i(a){return"null"},
gl(a){return 0},
gk(a){return A.a3(t.P)},
$ik:1,
$it:1}
J.bj.prototype={$iq:1}
J.ag.prototype={
gl(a){return 0},
gk(a){return B.aa},
i(a){return String(a)}}
J.cs.prototype={}
J.bC.prototype={}
J.a7.prototype={
i(a){var s=a[$.f7()]
if(s==null)return this.ba(a)
return"JavaScript function for "+J.aD(s)},
$iao:1}
J.aI.prototype={
gl(a){return 0},
i(a){return String(a)}}
J.aJ.prototype={
gl(a){return 0},
i(a){return String(a)}}
J.p.prototype={
j(a,b){A.c0(a).c.a(b)
a.$flags&1&&A.ae(a,29)
a.push(b)},
b2(a,b){var s
a.$flags&1&&A.ae(a,"removeAt",1)
s=a.length
if(b>=s)throw A.b(A.ft(b,null))
return a.splice(b,1)[0]},
F(a){a.$flags&1&&A.ae(a,"clear","clear")
a.length=0},
gb_(a){return a.length!==0},
i(a){return A.fk(a,"[","]")},
gu(a){return new J.b8(a,a.length,A.c0(a).h("b8<1>"))},
gl(a){return A.bv(a)},
gp(a){return a.length},
E(a,b,c){A.c0(a).c.a(c)
a.$flags&2&&A.ae(a)
if(!(b>=0&&b<a.length))throw A.b(A.h7(a,b))
a[b]=c},
gk(a){return A.a3(A.c0(a))},
$ii:1,
$id:1,
$im:1}
J.cl.prototype={
bP(a){var s,r,q
if(!Array.isArray(a))return null
s=a.$flags|0
if((s&4)!==0)r="const, "
else if((s&2)!==0)r="unmodifiable, "
else r=(s&1)!==0?"fixed, ":""
q="Instance of '"+A.ct(a)+"'"
if(r==="")return q
return q+" ("+r+"length: "+a.length+")"}}
J.d8.prototype={}
J.b8.prototype={
gq(){var s=this.d
return s==null?this.$ti.c.a(s):s},
n(){var s,r=this,q=r.a,p=q.length
if(r.b!==p){q=A.an(q)
throw A.b(q)}s=r.c
if(s>=p){r.d=null
return!1}r.d=q[s]
r.c=s+1
return!0},
$iR:1}
J.bi.prototype={
b5(a){var s
if(a>=-2147483648&&a<=2147483647)return a|0
if(isFinite(a)){s=a<0?Math.ceil(a):Math.floor(a)
return s+0}throw A.b(A.bE(""+a+".toInt()"))},
i(a){if(a===0&&1/a<0)return"-0.0"
else return""+a},
gl(a){var s,r,q,p,o=a|0
if(a===o)return o&536870911
s=Math.abs(a)
r=Math.log(s)/0.6931471805599453|0
q=Math.pow(2,r)
p=s<1?s/q:q/s
return((p*9007199254740992|0)+(p*3542243181176521|0))*599197+r*1259&536870911},
av(a,b){if((a|0)===a)if(b>=1||b<-1)return a/b|0
return this.aS(a,b)},
ae(a,b){return(a|0)===a?a/b|0:this.aS(a,b)},
aS(a,b){var s=a/b
if(s>=-2147483648&&s<=2147483647)return s|0
if(s>0){if(s!==1/0)return Math.floor(s)}else if(s>-1/0)return Math.ceil(s)
throw A.b(A.bE("Result of truncating division is "+A.j(s)+": "+A.j(a)+" ~/ "+b))},
aQ(a,b){var s
if(a>0)s=this.bv(a,b)
else{s=b>31?31:b
s=a>>s>>>0}return s},
bv(a,b){return b>31?0:a>>>b},
gk(a){return A.a3(t.o)},
$il:1,
$iaC:1}
J.bg.prototype={
gk(a){return A.a3(t.S)},
$ik:1,
$ia:1}
J.cn.prototype={
gk(a){return A.a3(t.i)},
$ik:1}
J.aH.prototype={
R(a,b,c){return a.substring(b,A.eI(b,c,a.length))},
b9(a,b){var s,r
if(0>=b)return""
if(b===1||a.length===0)return a
if(b!==b>>>0)throw A.b(B.N)
for(s=a,r="";;){if((b&1)===1)r=s+r
b=b>>>1
if(b===0)break
s+=s}return r},
bK(a,b,c){var s=b-a.length
if(s<=0)return a
return this.b9(c,s)+a},
i(a){return a},
gl(a){var s,r,q
for(s=a.length,r=0,q=0;q<s;++q){r=r+a.charCodeAt(q)&536870911
r=r+((r&524287)<<10)&536870911
r^=r>>6}r=r+((r&67108863)<<3)&536870911
r^=r>>11
return r+((r&16383)<<15)&536870911},
gk(a){return A.a3(t.N)},
gp(a){return a.length},
$ik:1,
$ifp:1,
$iL:1}
A.aK.prototype={
i(a){return"LateInitializationError: "+this.a}}
A.ev.prototype={
$0(){var s=new A.e($.f,t.D)
s.K(null)
return s},
$S:10}
A.di.prototype={}
A.i.prototype={}
A.bo.prototype={
gq(){var s=this.d
return s==null?this.$ti.c.a(s):s},
n(){var s,r=this,q=r.a,p=J.h8(q),o=p.gp(q)
if(r.b!==o)throw A.b(A.ce(q))
s=r.c
if(s>=o){r.d=null
return!1}r.d=p.aX(q,s);++r.c
return!0},
$iR:1}
A.as.prototype={
gu(a){var s=this.a
return new A.bq(s.gu(s),this.b,A.o(this).h("bq<1,2>"))},
gp(a){var s=this.a
return s.gp(s)}}
A.bd.prototype={$ii:1}
A.bq.prototype={
n(){var s=this,r=s.b
if(r.n()){s.a=s.c.$1(r.gq())
return!0}s.a=null
return!1},
gq(){var s=this.a
return s==null?this.$ti.y[1].a(s):s},
$iR:1}
A.D.prototype={}
A.bO.prototype={$r:"+(1,2)",$s:1}
A.ba.prototype={
gao(a){return this.gp(this)===0},
i(a){return A.eH(this)},
ga2(){return new A.b0(this.bD(),A.o(this).h("b0<E<1,2>>"))},
bD(){var s=this
return function(){var r=0,q=1,p=[],o,n,m,l,k
return function $async$ga2(a,b,c){if(b===1){p.push(c)
r=q}for(;;)switch(r){case 0:o=s.gbH(),o=o.gu(o),n=A.o(s),m=n.y[1],n=n.h("E<1,2>")
case 2:if(!o.n()){r=3
break}l=o.gq()
k=s.m(0,l)
r=4
return a.b=new A.E(l,k==null?m.a(k):k,n),1
case 4:r=2
break
case 3:return 0
case 1:return a.c=p.at(-1),3}}}},
$iar:1}
A.bb.prototype={
gp(a){return this.b.length},
gaK(){var s=this.$keys
if(s==null){s=Object.keys(this.a)
this.$keys=s}return s},
a0(a){if(typeof a!="string")return!1
if("__proto__"===a)return!1
return this.a.hasOwnProperty(a)},
m(a,b){if(!this.a0(b))return null
return this.b[this.a[b]]},
I(a,b){var s,r,q,p
this.$ti.h("~(1,2)").a(b)
s=this.gaK()
r=this.b
for(q=s.length,p=0;p<q;++p)b.$2(s[p],r[p])},
gbH(){return new A.bI(this.gaK(),this.$ti.h("bI<1>"))}}
A.bI.prototype={
gp(a){return this.a.length},
gu(a){var s=this.a
return new A.bJ(s,s.length,this.$ti.h("bJ<1>"))}}
A.bJ.prototype={
gq(){var s=this.d
return s==null?this.$ti.c.a(s):s},
n(){var s=this,r=s.c
if(r>=s.b){s.d=null
return!1}s.d=s.a[r]
s.c=r+1
return!0},
$iR:1}
A.by.prototype={}
A.dn.prototype={
A(a){var s,r,q=this,p=new RegExp(q.a).exec(a)
if(p==null)return null
s=Object.create(null)
r=q.b
if(r!==-1)s.arguments=p[r+1]
r=q.c
if(r!==-1)s.argumentsExpr=p[r+1]
r=q.d
if(r!==-1)s.expr=p[r+1]
r=q.e
if(r!==-1)s.method=p[r+1]
r=q.f
if(r!==-1)s.receiver=p[r+1]
return s}}
A.bu.prototype={
i(a){return"Null check operator used on a null value"}}
A.co.prototype={
i(a){var s,r=this,q="NoSuchMethodError: method not found: '",p=r.b
if(p==null)return"NoSuchMethodError: "+r.a
s=r.c
if(s==null)return q+p+"' ("+r.a+")"
return q+p+"' on '"+s+"' ("+r.a+")"}}
A.cB.prototype={
i(a){var s=this.a
return s.length===0?"Error":"Error: "+s}}
A.dh.prototype={
i(a){return"Throw of null ('"+(this.a===null?"null":"undefined")+"' from JavaScript)"}}
A.bf.prototype={}
A.bP.prototype={
i(a){var s,r=this.b
if(r!=null)return r
r=this.a
s=r!==null&&typeof r==="object"?r.stack:null
return this.b=s==null?"":s},
$ia0:1}
A.af.prototype={
i(a){var s=this.constructor,r=s==null?null:s.name
return"Closure '"+A.hh(r==null?"unknown":r)+"'"},
gk(a){var s=A.f1(this)
return A.a3(s==null?A.b5(this):s)},
$iao:1,
gbS(){return this},
$C:"$1",
$R:1,
$D:null}
A.c9.prototype={$C:"$0",$R:0}
A.ca.prototype={$C:"$2",$R:2}
A.cz.prototype={}
A.cx.prototype={
i(a){var s=this.$static_name
if(s==null)return"Closure of unknown static method"
return"Closure '"+A.hh(s)+"'"}}
A.aF.prototype={
D(a,b){if(b==null)return!1
if(this===b)return!0
if(!(b instanceof A.aF))return!1
return this.$_target===b.$_target&&this.a===b.a},
gl(a){return(A.hc(this.a)^A.bv(this.$_target))>>>0},
i(a){return"Closure '"+this.$_name+"' of "+("Instance of '"+A.ct(this.a)+"'")}}
A.cu.prototype={
i(a){return"RuntimeError: "+this.a}}
A.ap.prototype={
gp(a){return this.a},
gao(a){return this.a===0},
ga2(){return new A.bl(this,A.o(this).h("bl<1,2>"))},
a0(a){var s=this.b
if(s==null)return!1
return s[a]!=null},
m(a,b){var s,r,q,p,o=null
if(typeof b=="string"){s=this.b
if(s==null)return o
r=s[b]
q=r==null?o:r.b
return q}else if(typeof b=="number"&&(b&0x3fffffff)===b){p=this.c
if(p==null)return o
r=p[b]
q=r==null?o:r.b
return q}else return this.bG(b)},
bG(a){var s,r,q=this.d
if(q==null)return null
s=q[this.aY(a)]
r=this.aZ(s,a)
if(r<0)return null
return s[r].b},
E(a,b,c){var s,r,q,p,o,n,m=this,l=A.o(m)
l.c.a(b)
l.y[1].a(c)
if(typeof b=="string"){s=m.b
m.aw(s==null?m.b=m.a9():s,b,c)}else if(typeof b=="number"&&(b&0x3fffffff)===b){r=m.c
m.aw(r==null?m.c=m.a9():r,b,c)}else{q=m.d
if(q==null)q=m.d=m.a9()
p=m.aY(b)
o=q[p]
if(o==null)q[p]=[m.aa(b,c)]
else{n=m.aZ(o,b)
if(n>=0)o[n].b=c
else o.push(m.aa(b,c))}}},
I(a,b){var s,r,q=this
A.o(q).h("~(1,2)").a(b)
s=q.e
r=q.r
while(s!=null){b.$2(s.a,s.b)
if(r!==q.r)throw A.b(A.ce(q))
s=s.c}},
aw(a,b,c){var s,r=A.o(this)
r.c.a(b)
r.y[1].a(c)
s=a[b]
if(s==null)a[b]=this.aa(b,c)
else s.b=c},
aa(a,b){var s=this,r=A.o(s),q=new A.da(r.c.a(a),r.y[1].a(b))
if(s.e==null)s.e=s.f=q
else s.f=s.f.c=q;++s.a
s.r=s.r+1&1073741823
return q},
aY(a){return J.P(a)&1073741823},
aZ(a,b){var s,r
if(a==null)return-1
s=a.length
for(r=0;r<s;++r)if(J.eB(a[r].a,b))return r
return-1},
i(a){return A.eH(this)},
a9(){var s=Object.create(null)
s["<non-identifier-key>"]=s
delete s["<non-identifier-key>"]
return s},
$ifm:1}
A.da.prototype={}
A.bn.prototype={
gp(a){return this.a.a},
gu(a){var s=this.a
return new A.aq(s,s.r,s.e,this.$ti.h("aq<1>"))}}
A.aq.prototype={
gq(){return this.d},
n(){var s,r=this,q=r.a
if(r.b!==q.r)throw A.b(A.ce(q))
s=r.c
if(s==null){r.d=null
return!1}else{r.d=s.a
r.c=s.c
return!0}},
$iR:1}
A.bl.prototype={
gp(a){return this.a.a},
gu(a){var s=this.a
return new A.bm(s,s.r,s.e,this.$ti.h("bm<1,2>"))}}
A.bm.prototype={
gq(){var s=this.d
s.toString
return s},
n(){var s,r=this,q=r.a
if(r.b!==q.r)throw A.b(A.ce(q))
s=r.c
if(s==null){r.d=null
return!1}else{r.d=new A.E(s.a,s.b,r.$ti.h("E<1,2>"))
r.c=s.c
return!0}},
$iR:1}
A.eq.prototype={
$1(a){return this.a(a)},
$S:7}
A.er.prototype={
$2(a,b){return this.a(a,b)},
$S:11}
A.es.prototype={
$1(a){return this.a(A.a2(a))},
$S:12}
A.az.prototype={
gk(a){return A.a3(this.aJ())},
aJ(){return A.jc(this.$r,this.aI())},
i(a){return this.aU(!1)},
aU(a){var s,r,q,p,o,n=this.bi(),m=this.aI(),l=(a?"Record ":"")+"("
for(s=n.length,r="",q=0;q<s;++q,r=", "){l+=r
p=n[q]
if(typeof p=="string")l=l+p+": "
if(!(q<m.length))return A.h(m,q)
o=m[q]
l=a?l+A.fr(o):l+A.j(o)}l+=")"
return l.charCodeAt(0)==0?l:l},
bi(){var s,r=this.$s
while($.e1.length<=r)B.a.j($.e1,null)
s=$.e1[r]
if(s==null){s=this.bg()
B.a.E($.e1,r,s)}return s},
bg(){var s,r,q,p=this.$r,o=p.indexOf("("),n=p.substring(1,o),m=p.substring(o),l=m==="()"?0:m.replace(/[^,]/g,"").length+1,k=A.z(new Array(l),t.f)
for(s=0;s<l;++s)k[s]=s
if(n!==""){r=n.split(",")
s=r.length
for(q=l;s>0;){--q;--s
B.a.E(k,q,r[s])}}k=A.dc(k,!1,t.K)
k.$flags=3
return k}}
A.b_.prototype={
aI(){return[this.a,this.b]},
D(a,b){if(b==null)return!1
return b instanceof A.b_&&this.$s===b.$s&&J.eB(this.a,b.a)&&J.eB(this.b,b.b)},
gl(a){return A.fo(this.$s,this.a,this.b,B.d,B.d)}}
A.dG.prototype={}
A.ah.prototype={
gk(a){return B.a3},
aV(a,b,c){var s=new DataView(a,b,c)
return s},
$ik:1,
$iah:1,
$ib9:1}
A.aL.prototype={$iaL:1}
A.bt.prototype={
gby(a){if(((a.$flags|0)&2)!==0)return new A.cP(a.buffer)
else return a.buffer},
$iu:1}
A.cP.prototype={
aV(a,b,c){var s=A.hL(this.a,b,c)
s.$flags=3
return s},
$ib9:1}
A.aM.prototype={
gk(a){return B.a4},
$ik:1,
$iaM:1,
$icZ:1}
A.aS.prototype={
gp(a){return a.length},
$iK:1}
A.br.prototype={$ii:1,$id:1,$im:1}
A.bs.prototype={$ii:1,$id:1,$im:1}
A.aN.prototype={
gk(a){return B.a5},
$ik:1,
$iaN:1,
$id3:1}
A.aO.prototype={
gk(a){return B.a6},
$ik:1,
$iaO:1,
$id4:1}
A.aP.prototype={
gk(a){return B.a7},
$ik:1,
$iaP:1,
$id5:1}
A.aQ.prototype={
gk(a){return B.a8},
$ik:1,
$iaQ:1,
$id6:1}
A.aR.prototype={
gk(a){return B.a9},
$ik:1,
$iaR:1,
$id7:1}
A.aT.prototype={
gk(a){return B.ac},
$ik:1,
$iaT:1,
$idq:1}
A.aU.prototype={
gk(a){return B.ad},
$ik:1,
$iaU:1,
$idr:1}
A.at.prototype={
gk(a){return B.ae},
gp(a){return a.length},
$ik:1,
$iat:1,
$ids:1}
A.ai.prototype={
gk(a){return B.af},
gp(a){return a.length},
$ik:1,
$iai:1,
$ibB:1}
A.bK.prototype={}
A.bL.prototype={}
A.bM.prototype={}
A.bN.prototype={}
A.a_.prototype={
h(a){return A.bY(v.typeUniverse,this,a)},
t(a){return A.fN(v.typeUniverse,this,a)}}
A.cL.prototype={}
A.e7.prototype={
i(a){return A.C(this.a,null)}}
A.cK.prototype={
i(a){return this.a}}
A.bU.prototype={$ia9:1}
A.dC.prototype={
$1(a){var s=this.a,r=s.a
s.a=null
r.$0()},
$S:8}
A.dB.prototype={
$1(a){var s,r
this.a.a=t.M.a(a)
s=this.b
r=this.c
s.firstChild?s.removeChild(r):s.appendChild(r)},
$S:13}
A.dD.prototype={
$0(){this.a.$0()},
$S:2}
A.dE.prototype={
$0(){this.a.$0()},
$S:2}
A.e5.prototype={
bb(a,b){if(self.setTimeout!=null)this.b=self.setTimeout(A.c4(new A.e6(this,b),0),a)
else throw A.b(A.bE("`setTimeout()` not found."))},
ak(){if(self.setTimeout!=null){var s=this.b
if(s==null)return
self.clearTimeout(s)
this.b=null}else throw A.b(A.bE("Canceling a timer."))}}
A.e6.prototype={
$0(){this.a.b=null
this.b.$0()},
$S:0}
A.bF.prototype={
a_(a){var s,r=this,q=r.$ti
q.h("1/?").a(a)
if(a==null)a=q.c.a(a)
if(!r.b)r.a.K(a)
else{s=r.a
if(q.h("A<1>").b(a))s.aD(a)
else s.a6(a)}},
am(a,b){var s=this.a
if(this.b)s.H(new A.x(a,b))
else s.L(new A.x(a,b))},
$id0:1}
A.eg.prototype={
$1(a){return this.a.$2(0,a)},
$S:4}
A.eh.prototype={
$2(a,b){this.a.$2(1,new A.bf(a,t.l.a(b)))},
$S:14}
A.em.prototype={
$2(a,b){this.a(A.F(a),b)},
$S:15}
A.bT.prototype={
gq(){var s=this.b
return s==null?this.$ti.c.a(s):s},
bs(a,b){var s,r,q
a=A.F(a)
b=b
s=this.a
for(;;)try{r=s(this,a,b)
return r}catch(q){b=q
a=1}},
n(){var s,r,q,p,o=this,n=null,m=0
for(;;){s=o.d
if(s!=null)try{if(s.n()){o.b=s.gq()
return!0}else o.d=null}catch(r){n=r
m=1
o.d=null}q=o.bs(m,n)
if(1===q)return!0
if(0===q){o.b=null
p=o.e
if(p==null||p.length===0){o.a=A.fI
return!1}if(0>=p.length)return A.h(p,-1)
o.a=p.pop()
m=0
n=null
continue}if(2===q){m=0
n=null
continue}if(3===q){n=o.c
o.c=null
p=o.e
if(p==null||p.length===0){o.b=null
o.a=A.fI
throw n
return!1}if(0>=p.length)return A.h(p,-1)
o.a=p.pop()
m=1
continue}throw A.b(A.a8("sync*"))}return!1},
bT(a){var s,r,q=this
if(a instanceof A.b0){s=a.a()
r=q.e
if(r==null)r=q.e=[]
B.a.j(r,q.a)
q.a=s
return 2}else{q.d=J.eC(a)
return 2}},
$iR:1}
A.b0.prototype={
gu(a){return new A.bT(this.a(),this.$ti.h("bT<1>"))}}
A.x.prototype={
i(a){return A.j(this.a)},
$in:1,
gJ(){return this.b}}
A.bH.prototype={
am(a,b){var s=this.a
if((s.a&30)!==0)throw A.b(A.a8("Future already completed"))
s.L(A.iz(a,b))},
aW(a){return this.am(a,null)},
$id0:1}
A.a6.prototype={
a_(a){var s,r=this.$ti
r.h("1/?").a(a)
s=this.a
if((s.a&30)!==0)throw A.b(A.a8("Future already completed"))
s.K(r.h("1/").a(a))},
al(){return this.a_(null)}}
A.ab.prototype={
bJ(a){if((this.c&15)!==6)return!0
return this.b.b.ar(t.bN.a(this.d),a.a,t.y,t.K)},
bE(a){var s,r=this,q=r.e,p=null,o=t.z,n=t.K,m=a.a,l=r.b.b
if(t.Q.b(q))p=l.bM(q,m,a.b,o,n,t.l)
else p=l.ar(t.v.a(q),m,o,n)
try{o=r.$ti.h("2/").a(p)
return o}catch(s){if(t.eK.b(A.H(s))){if((r.c&1)!==0)throw A.b(A.c5("The error handler of Future.then must return a value of the returned future's type","onError"))
throw A.b(A.c5("The error handler of Future.catchError must return a value of the future's type","onError"))}else throw s}}}
A.e.prototype={
P(a,b,c){var s,r,q,p=this.$ti
p.t(c).h("1/(2)").a(a)
s=$.f
if(s===B.b){if(b!=null&&!t.Q.b(b)&&!t.v.b(b))throw A.b(A.aE(b,"onError",u.c))}else{c.h("@<0/>").t(p.c).h("1(2)").a(a)
if(b!=null)b=A.iP(b,s)}r=new A.e(s,c.h("e<0>"))
q=b==null?1:3
this.S(new A.ab(r,q,a,b,p.h("@<1>").t(c).h("ab<1,2>")))
return r},
bO(a,b){return this.P(a,null,b)},
aT(a,b,c){var s,r=this.$ti
r.t(c).h("1/(2)").a(a)
s=new A.e($.f,c.h("e<0>"))
this.S(new A.ab(s,19,a,b,r.h("@<1>").t(c).h("ab<1,2>")))
return s},
au(a){var s,r
t.O.a(a)
s=this.$ti
r=new A.e($.f,s)
this.S(new A.ab(r,8,a,null,s.h("ab<1,1>")))
return r},
bt(a){this.a=this.a&1|16
this.c=a},
U(a){this.a=a.a&30|this.a&1
this.c=a.c},
S(a){var s,r=this,q=r.a
if(q<=3){a.a=t.F.a(r.c)
r.c=a}else{if((q&4)!==0){s=t._.a(r.c)
if((s.a&24)===0){s.S(a)
return}r.U(s)}A.b2(null,null,r.b,t.M.a(new A.dJ(r,a)))}},
aP(a){var s,r,q,p,o,n,m=this,l={}
l.a=a
if(a==null)return
s=m.a
if(s<=3){r=t.F.a(m.c)
m.c=a
if(r!=null){q=a.a
for(p=a;q!=null;p=q,q=o)o=q.a
p.a=r}}else{if((s&4)!==0){n=t._.a(m.c)
if((n.a&24)===0){n.aP(a)
return}m.U(n)}l.a=m.V(a)
A.b2(null,null,m.b,t.M.a(new A.dO(l,m)))}},
N(){var s=t.F.a(this.c)
this.c=null
return this.V(s)},
V(a){var s,r,q
for(s=a,r=null;s!=null;r=s,s=q){q=s.a
s.a=r}return r},
aF(a){var s,r=this,q=r.$ti
q.h("1/").a(a)
if(q.h("A<1>").b(a))A.dM(a,r,!0)
else{s=r.N()
q.c.a(a)
r.a=8
r.c=a
A.ax(r,s)}},
a6(a){var s,r=this
r.$ti.c.a(a)
s=r.N()
r.a=8
r.c=a
A.ax(r,s)},
bf(a){var s,r,q=this
if((a.a&16)!==0){s=q.b===a.b
s=!(s||s)}else s=!1
if(s)return
r=q.N()
q.U(a)
A.ax(q,r)},
H(a){var s=this.N()
this.bt(a)
A.ax(this,s)},
be(a,b){A.T(a)
t.l.a(b)
this.H(new A.x(a,b))},
K(a){var s=this.$ti
s.h("1/").a(a)
if(s.h("A<1>").b(a)){this.aD(a)
return}this.bc(a)},
bc(a){var s=this
s.$ti.c.a(a)
s.a^=2
A.b2(null,null,s.b,t.M.a(new A.dL(s,a)))},
aD(a){A.dM(this.$ti.h("A<1>").a(a),this,!1)
return},
L(a){this.a^=2
A.b2(null,null,this.b,t.M.a(new A.dK(this,a)))},
b4(a,b){var s,r,q=this,p={},o=q.$ti
o.h("1/()?").a(b)
if((q.a&24)!==0){p=new A.e($.f,o)
p.K(q)
return p}s=$.f
r=new A.e(s,o)
p.a=null
p.a=A.hR(a,new A.dU(q,r,s,o.h("1/()").a(b)))
q.P(new A.dV(p,q,r),new A.dW(p,r),t.P)
return r},
$iA:1}
A.dJ.prototype={
$0(){A.ax(this.a,this.b)},
$S:0}
A.dO.prototype={
$0(){A.ax(this.b,this.a.a)},
$S:0}
A.dN.prototype={
$0(){A.dM(this.a.a,this.b,!0)},
$S:0}
A.dL.prototype={
$0(){this.a.a6(this.b)},
$S:0}
A.dK.prototype={
$0(){this.a.H(this.b)},
$S:0}
A.dR.prototype={
$0(){var s,r,q,p,o,n,m,l,k=this,j=null
try{q=k.a.a
j=q.b.b.aq(t.O.a(q.d),t.z)}catch(p){s=A.H(p)
r=A.I(p)
if(k.c&&t.n.a(k.b.a.c).a===s){q=k.a
q.c=t.n.a(k.b.a.c)}else{q=s
o=r
if(o==null)o=A.c8(q)
n=k.a
n.c=new A.x(q,o)
q=n}q.b=!0
return}if(j instanceof A.e&&(j.a&24)!==0){if((j.a&16)!==0){q=k.a
q.c=t.n.a(j.c)
q.b=!0}return}if(j instanceof A.e){m=k.b.a
l=new A.e(m.b,m.$ti)
j.P(new A.dS(l,m),new A.dT(l),t.H)
q=k.a
q.c=l
q.b=!1}},
$S:0}
A.dS.prototype={
$1(a){this.a.bf(this.b)},
$S:8}
A.dT.prototype={
$2(a,b){A.T(a)
t.l.a(b)
this.a.H(new A.x(a,b))},
$S:5}
A.dQ.prototype={
$0(){var s,r,q,p,o,n,m,l
try{q=this.a
p=q.a
o=p.$ti
n=o.c
m=n.a(this.b)
q.c=p.b.b.ar(o.h("2/(1)").a(p.d),m,o.h("2/"),n)}catch(l){s=A.H(l)
r=A.I(l)
q=s
p=r
if(p==null)p=A.c8(q)
o=this.a
o.c=new A.x(q,p)
o.b=!0}},
$S:0}
A.dP.prototype={
$0(){var s,r,q,p,o,n,m,l=this
try{s=t.n.a(l.a.a.c)
p=l.b
if(p.a.bJ(s)&&p.a.e!=null){p.c=p.a.bE(s)
p.b=!1}}catch(o){r=A.H(o)
q=A.I(o)
p=t.n.a(l.a.a.c)
if(p.a===r){n=l.b
n.c=p
p=n}else{p=r
n=q
if(n==null)n=A.c8(p)
m=l.b
m.c=new A.x(p,n)
p=m}p.b=!0}},
$S:0}
A.dU.prototype={
$0(){var s,r,q,p,o,n=this
try{n.b.aF(n.c.aq(n.d,n.a.$ti.h("1/")))}catch(q){s=A.H(q)
r=A.I(q)
p=s
o=r
if(o==null)o=A.c8(p)
n.b.H(new A.x(p,o))}},
$S:0}
A.dV.prototype={
$1(a){var s
this.b.$ti.c.a(a)
s=this.a.a
if(s.b!=null){s.ak()
this.c.a6(a)}},
$S(){return this.b.$ti.h("t(1)")}}
A.dW.prototype={
$2(a,b){var s
A.T(a)
t.l.a(b)
s=this.a.a
if(s.b!=null){s.ak()
this.b.H(new A.x(a,b))}},
$S:5}
A.cG.prototype={}
A.bA.prototype={
gp(a){var s={},r=new A.e($.f,t.fJ)
s.a=0
this.b0(new A.dk(s,this),!0,new A.dl(s,r),r.gbd())
return r}}
A.dk.prototype={
$1(a){this.b.$ti.c.a(a);++this.a.a},
$S(){return this.b.$ti.h("~(1)")}}
A.dl.prototype={
$0(){this.b.aF(this.a.a)},
$S:0}
A.bQ.prototype={
gbq(){var s,r=this
if((r.b&8)===0)return A.o(r).h("a1<1>?").a(r.a)
s=A.o(r)
return s.h("a1<1>?").a(s.h("bR<1>").a(r.a).gaf())},
aH(){var s,r,q=this
if((q.b&8)===0){s=q.a
if(s==null)s=q.a=new A.a1(A.o(q).h("a1<1>"))
return A.o(q).h("a1<1>").a(s)}r=A.o(q)
s=r.h("bR<1>").a(q.a).gaf()
return r.h("a1<1>").a(s)},
gaR(){var s=this.a
if((this.b&8)!==0)s=t.fv.a(s).gaf()
return A.o(this).h("aZ<1>").a(s)},
aB(){if((this.b&4)!==0)return new A.au("Cannot add event after closing")
return new A.au("Cannot add event while adding a stream")},
aG(){var s=this.c
if(s==null)s=this.c=(this.b&2)!==0?$.eA():new A.e($.f,t.D)
return s},
j(a,b){var s,r=this,q=A.o(r)
q.c.a(b)
s=r.b
if(s>=4)throw A.b(r.aB())
if((s&1)!==0)r.ac(b)
else if((s&3)===0)r.aH().j(0,new A.av(b,q.h("av<1>")))},
v(){var s=this,r=s.b
if((r&4)!==0)return s.aG()
if(r>=4)throw A.b(s.aB())
r=s.b=r|4
if((r&1)!==0)s.ad()
else if((r&3)===0)s.aH().j(0,B.v)
return s.aG()},
bw(a,b,c,d){var s,r,q,p,o,n,m,l=this,k=A.o(l)
k.h("~(1)?").a(a)
t.b.a(c)
if((l.b&3)!==0)throw A.b(A.a8("Stream has already been listened to."))
s=$.f
r=d?1:0
q=b!=null?32:0
t.r.t(k.c).h("1(2)").a(a)
A.hY(s,b)
p=t.M
o=new A.aZ(l,a,p.a(c),s,r|q,k.h("aZ<1>"))
n=l.gbq()
if(((l.b|=1)&8)!==0){m=k.h("bR<1>").a(l.a)
m.saf(o)
m.bL()}else l.a=o
o.bu(n)
k=p.a(new A.e4(l))
s=o.e
o.e=s|64
k.$0()
o.e&=4294967231
o.aE((s&4)!==0)
return o},
br(a){var s,r,q,p,o,n,m,l,k=this,j=A.o(k)
j.h("cy<1>").a(a)
s=null
if((k.b&8)!==0)s=j.h("bR<1>").a(k.a).ak()
k.a=null
k.b=k.b&4294967286|2
r=k.r
if(r!=null)if(s==null)try{q=r.$0()
if(q instanceof A.e)s=q}catch(n){p=A.H(n)
o=A.I(n)
m=new A.e($.f,t.D)
j=A.T(p)
l=t.l.a(o)
m.L(new A.x(j,l))
s=m}else s=s.au(r)
j=new A.e3(k)
if(s!=null)s=s.au(j)
else j.$0()
return s},
$ifv:1,
$ifH:1,
$iaw:1}
A.e4.prototype={
$0(){A.eX(this.a.d)},
$S:0}
A.e3.prototype={
$0(){var s=this.a.c
if(s!=null&&(s.a&30)===0)s.K(null)},
$S:0}
A.cH.prototype={
ac(a){var s=this.$ti
s.c.a(a)
this.gaR().az(new A.av(a,s.h("av<1>")))},
ad(){this.gaR().az(B.v)}}
A.aX.prototype={}
A.aY.prototype={
gl(a){return(A.bv(this.a)^892482866)>>>0},
D(a,b){if(b==null)return!1
if(this===b)return!0
return b instanceof A.aY&&b.a===this.a}}
A.aZ.prototype={
aL(){return this.w.br(this)},
aM(){var s=this.w,r=A.o(s)
r.h("cy<1>").a(this)
if((s.b&8)!==0)r.h("bR<1>").a(s.a).bU()
A.eX(s.e)},
aN(){var s=this.w,r=A.o(s)
r.h("cy<1>").a(this)
if((s.b&8)!==0)r.h("bR<1>").a(s.a).bL()
A.eX(s.f)}}
A.bG.prototype={
bu(a){var s=this
A.o(s).h("a1<1>?").a(a)
if(a==null)return
s.r=a
if(a.c!=null){s.e|=128
a.a4(s)}},
aC(){var s,r=this,q=r.e|=8
if((q&128)!==0){s=r.r
if(s.a===1)s.a=3}if((q&64)===0)r.r=null
r.f=r.aL()},
aM(){},
aN(){},
aL(){return null},
az(a){var s,r=this,q=r.r
if(q==null)q=r.r=new A.a1(A.o(r).h("a1<1>"))
q.j(0,a)
s=r.e
if((s&128)===0){s|=128
r.e=s
if(s<256)q.a4(r)}},
ac(a){var s,r=this,q=A.o(r).c
q.a(a)
s=r.e
r.e=s|64
r.d.bN(r.a,a,q)
r.e&=4294967231
r.aE((s&4)!==0)},
ad(){var s,r=this,q=new A.dF(r)
r.aC()
r.e|=16
s=r.f
if(s!=null&&s!==$.eA())s.au(q)
else q.$0()},
aE(a){var s,r,q=this,p=q.e
if((p&128)!==0&&q.r.c==null){p=q.e=p&4294967167
s=!1
if((p&4)!==0)if(p<256){s=q.r
s=s==null?null:s.c==null
s=s!==!1}if(s){p&=4294967291
q.e=p}}for(;;a=r){if((p&8)!==0){q.r=null
return}r=(p&4)!==0
if(a===r)break
q.e=p^64
if(r)q.aM()
else q.aN()
p=q.e&=4294967231}if((p&128)!==0&&p<256)q.r.a4(q)},
$icy:1,
$iaw:1}
A.dF.prototype={
$0(){var s=this.a,r=s.e
if((r&16)===0)return
s.e=r|74
s.d.b3(s.c)
s.e&=4294967231},
$S:0}
A.bS.prototype={
b0(a,b,c,d){var s=this.$ti
s.h("~(1)?").a(a)
t.b.a(c)
return this.a.bw(s.h("~(1)?").a(a),d,c,b===!0)},
bI(a,b){return this.b0(a,null,b,null)}}
A.aj.prototype={
sO(a){this.a=t.ev.a(a)},
gO(){return this.a}}
A.av.prototype={
b1(a){this.$ti.h("aw<1>").a(a).ac(this.b)}}
A.cI.prototype={
b1(a){a.ad()},
gO(){return null},
sO(a){throw A.b(A.a8("No events after a done."))},
$iaj:1}
A.a1.prototype={
a4(a){var s,r=this
r.$ti.h("aw<1>").a(a)
s=r.a
if(s===1)return
if(s>=1){r.a=1
return}A.jr(new A.e0(r,a))
r.a=1},
j(a,b){var s=this,r=s.c
if(r==null)s.b=s.c=b
else{r.sO(b)
s.c=b}}}
A.e0.prototype={
$0(){var s,r,q,p=this.a,o=p.a
p.a=0
if(o===3)return
s=p.$ti.h("aw<1>").a(this.b)
r=p.b
q=r.gO()
p.b=q
if(q==null)p.c=null
r.b1(s)},
$S:0}
A.cN.prototype={}
A.c_.prototype={$ifA:1}
A.cM.prototype={
b3(a){var s,r,q
t.M.a(a)
try{if(B.b===$.f){a.$0()
return}A.h0(null,null,this,a,t.H)}catch(q){s=A.H(q)
r=A.I(q)
A.cU(A.T(s),t.l.a(r))}},
bN(a,b,c){var s,r,q
c.h("~(0)").a(a)
c.a(b)
try{if(B.b===$.f){a.$1(b)
return}A.h1(null,null,this,a,b,t.H,c)}catch(q){s=A.H(q)
r=A.I(q)
A.cU(A.T(s),t.l.a(r))}},
aj(a){return new A.e2(this,t.M.a(a))},
aq(a,b){b.h("0()").a(a)
if($.f===B.b)return a.$0()
return A.h0(null,null,this,a,b)},
ar(a,b,c,d){c.h("@<0>").t(d).h("1(2)").a(a)
d.a(b)
if($.f===B.b)return a.$1(b)
return A.h1(null,null,this,a,b,c,d)},
bM(a,b,c,d,e,f){d.h("@<0>").t(e).t(f).h("1(2,3)").a(a)
e.a(b)
f.a(c)
if($.f===B.b)return a.$2(b,c)
return A.iQ(null,null,this,a,b,c,d,e,f)},
ap(a,b,c,d){return b.h("@<0>").t(c).t(d).h("1(2,3)").a(a)}}
A.e2.prototype={
$0(){return this.a.b3(this.b)},
$S:0}
A.ej.prototype={
$0(){A.hF(this.a,this.b)},
$S:0}
A.r.prototype={
gu(a){return new A.bo(a,a.length,A.b5(a).h("bo<r.E>"))},
aX(a,b){if(!(b<a.length))return A.h(a,b)
return a[b]},
gb_(a){return a.length!==0},
i(a){return A.fk(a,"[","]")}}
A.bp.prototype={
I(a,b){var s,r,q,p=this,o=A.o(p)
o.h("~(1,2)").a(b)
for(s=new A.aq(p,p.r,p.e,o.h("aq<1>")),o=o.y[1];s.n();){r=s.d
q=p.m(0,r)
b.$2(r,q==null?o.a(q):q)}},
ga2(){var s=A.o(this),r=s.h("bn<1>")
s=s.h("E<1,2>")
return A.hK(new A.bn(this,r),r.t(s).h("1(d.E)").a(new A.dd(this)),r.h("d.E"),s)},
gp(a){return this.a},
gao(a){return this.a===0},
i(a){return A.eH(this)},
$iar:1}
A.dd.prototype={
$1(a){var s=this.a,r=A.o(s)
r.c.a(a)
s=s.m(0,a)
if(s==null)s=r.y[1].a(s)
return new A.E(a,s,r.h("E<1,2>"))},
$S(){return A.o(this.a).h("E<1,2>(1)")}}
A.de.prototype={
$2(a,b){var s,r=this.a
if(!r.a)this.b.a+=", "
r.a=!1
r=this.b
s=A.j(a)
r.a=(r.a+=s)+": "
s=A.j(b)
r.a+=s},
$S:3}
A.cb.prototype={}
A.cf.prototype={}
A.bk.prototype={
i(a){var s=A.ch(this.a)
return(this.b!=null?"Converting object to an encodable object failed:":"Converting object did not return an encodable object:")+" "+s}}
A.cq.prototype={
i(a){return"Cyclic error in JSON stringify"}}
A.cp.prototype={
bB(a,b){var s=A.i0(a,this.gbC().b,null)
return s},
gbC(){return B.V}}
A.d9.prototype={}
A.dZ.prototype={
b8(a){var s,r,q,p,o,n,m=a.length
for(s=this.c,r=0,q=0;q<m;++q){p=a.charCodeAt(q)
if(p>92){if(p>=55296){o=p&64512
if(o===55296){n=q+1
n=!(n<m&&(a.charCodeAt(n)&64512)===56320)}else n=!1
if(!n)if(o===56320){o=q-1
o=!(o>=0&&(a.charCodeAt(o)&64512)===55296)}else o=!1
else o=!0
if(o){if(q>r)s.a+=B.f.R(a,r,q)
r=q+1
o=A.y(92)
s.a+=o
o=A.y(117)
s.a+=o
o=A.y(100)
s.a+=o
o=p>>>8&15
o=A.y(o<10?48+o:87+o)
s.a+=o
o=p>>>4&15
o=A.y(o<10?48+o:87+o)
s.a+=o
o=p&15
o=A.y(o<10?48+o:87+o)
s.a+=o}}continue}if(p<32){if(q>r)s.a+=B.f.R(a,r,q)
r=q+1
o=A.y(92)
s.a+=o
switch(p){case 8:o=A.y(98)
s.a+=o
break
case 9:o=A.y(116)
s.a+=o
break
case 10:o=A.y(110)
s.a+=o
break
case 12:o=A.y(102)
s.a+=o
break
case 13:o=A.y(114)
s.a+=o
break
default:o=A.y(117)
s.a+=o
o=A.y(48)
s.a=(s.a+=o)+o
o=p>>>4&15
o=A.y(o<10?48+o:87+o)
s.a+=o
o=p&15
o=A.y(o<10?48+o:87+o)
s.a+=o
break}}else if(p===34||p===92){if(q>r)s.a+=B.f.R(a,r,q)
r=q+1
o=A.y(92)
s.a+=o
o=A.y(p)
s.a+=o}}if(r===0)s.a+=a
else if(r<m)s.a+=B.f.R(a,r,m)},
a5(a){var s,r,q,p
for(s=this.a,r=s.length,q=0;q<r;++q){p=s[q]
if(a==null?p==null:a===p)throw A.b(new A.cq(a,null))}B.a.j(s,a)},
a3(a){var s,r,q,p,o=this
if(o.b7(a))return
o.a5(a)
try{s=o.b.$1(a)
if(!o.b7(s)){q=A.fl(a,null,o.gaO())
throw A.b(q)}q=o.a
if(0>=q.length)return A.h(q,-1)
q.pop()}catch(p){r=A.H(p)
q=A.fl(a,r,o.gaO())
throw A.b(q)}},
b7(a){var s,r,q=this
if(typeof a=="number"){if(!isFinite(a))return!1
q.c.a+=B.j.i(a)
return!0}else if(a===!0){q.c.a+="true"
return!0}else if(a===!1){q.c.a+="false"
return!0}else if(a==null){q.c.a+="null"
return!0}else if(typeof a=="string"){s=q.c
s.a+='"'
q.b8(a)
s.a+='"'
return!0}else if(t.j.b(a)){q.a5(a)
q.bQ(a)
s=q.a
if(0>=s.length)return A.h(s,-1)
s.pop()
return!0}else if(t.G.b(a)){q.a5(a)
r=q.bR(a)
s=q.a
if(0>=s.length)return A.h(s,-1)
s.pop()
return r}else return!1},
bQ(a){var s,r=this.c
r.a+="["
if(J.hw(a)){if(0>=a.length)return A.h(a,0)
this.a3(a[0])
for(s=1;s<a.length;++s){r.a+=","
this.a3(a[s])}}r.a+="]"},
bR(a){var s,r,q,p,o,n,m=this,l={}
if(a.gao(a)){m.c.a+="{}"
return!0}s=a.gp(a)*2
r=A.hJ(s,null,t.X)
q=l.a=0
l.b=!0
a.I(0,new A.e_(l,r))
if(!l.b)return!1
p=m.c
p.a+="{"
for(o='"';q<s;q+=2,o=',"'){p.a+=o
m.b8(A.a2(r[q]))
p.a+='":'
n=q+1
if(!(n<s))return A.h(r,n)
m.a3(r[n])}p.a+="}"
return!0}}
A.e_.prototype={
$2(a,b){var s,r
if(typeof a!="string")this.a.b=!1
s=this.b
r=this.a
B.a.E(s,r.a++,a)
B.a.E(s,r.a++,b)},
$S:3}
A.dY.prototype={
gaO(){var s=this.c.a
return s.charCodeAt(0)==0?s:s}}
A.dt.prototype={
a1(a){var s,r,q,p,o=a.length,n=A.eI(0,null,o)
if(n===0)return new Uint8Array(0)
s=n*3
r=new Uint8Array(s)
q=new A.e9(r)
if(q.bj(a,0,n)!==n){p=n-1
if(!(p>=0&&p<o))return A.h(a,p)
q.ai()}return new Uint8Array(r.subarray(0,A.io(0,q.b,s)))}}
A.e9.prototype={
ai(){var s,r=this,q=r.c,p=r.b,o=r.b=p+1
q.$flags&2&&A.ae(q)
s=q.length
if(!(p<s))return A.h(q,p)
q[p]=239
p=r.b=o+1
if(!(o<s))return A.h(q,o)
q[o]=191
r.b=p+1
if(!(p<s))return A.h(q,p)
q[p]=189},
bx(a,b){var s,r,q,p,o,n=this
if((b&64512)===56320){s=65536+((a&1023)<<10)|b&1023
r=n.c
q=n.b
p=n.b=q+1
r.$flags&2&&A.ae(r)
o=r.length
if(!(q<o))return A.h(r,q)
r[q]=s>>>18|240
q=n.b=p+1
if(!(p<o))return A.h(r,p)
r[p]=s>>>12&63|128
p=n.b=q+1
if(!(q<o))return A.h(r,q)
r[q]=s>>>6&63|128
n.b=p+1
if(!(p<o))return A.h(r,p)
r[p]=s&63|128
return!0}else{n.ai()
return!1}},
bj(a,b,c){var s,r,q,p,o,n,m,l,k=this
if(b!==c){s=c-1
if(!(s>=0&&s<a.length))return A.h(a,s)
s=(a.charCodeAt(s)&64512)===55296}else s=!1
if(s)--c
for(s=k.c,r=s.$flags|0,q=s.length,p=a.length,o=b;o<c;++o){if(!(o<p))return A.h(a,o)
n=a.charCodeAt(o)
if(n<=127){m=k.b
if(m>=q)break
k.b=m+1
r&2&&A.ae(s)
s[m]=n}else{m=n&64512
if(m===55296){if(k.b+4>q)break
m=o+1
if(!(m<p))return A.h(a,m)
if(k.bx(n,a.charCodeAt(m)))o=m}else if(m===56320){if(k.b+3>q)break
k.ai()}else if(n<=2047){m=k.b
l=m+1
if(l>=q)break
k.b=l
r&2&&A.ae(s)
if(!(m<q))return A.h(s,m)
s[m]=n>>>6|192
k.b=l+1
s[l]=n&63|128}else{m=k.b
if(m+2>=q)break
l=k.b=m+1
r&2&&A.ae(s)
if(!(m<q))return A.h(s,m)
s[m]=n>>>12|224
m=k.b=l+1
if(!(l<q))return A.h(s,l)
s[l]=n>>>6&63|128
k.b=m+1
if(!(m<q))return A.h(s,m)
s[m]=n&63|128}}}return o}}
A.bc.prototype={
D(a,b){if(b==null)return!1
return b instanceof A.bc&&this.a===b.a},
gl(a){return B.c.gl(this.a)},
i(a){var s,r,q,p=this.a,o=p%36e8,n=B.c.ae(o,6e7)
o%=6e7
s=n<10?"0":""
r=B.c.ae(o,1e6)
q=r<10?"0":""
return""+(p/36e8|0)+":"+s+n+":"+q+r+"."+B.f.bK(B.c.i(o%1e6),6,"0")}}
A.cJ.prototype={
i(a){return this.M()},
$ibe:1}
A.n.prototype={
gJ(){return A.hM(this)}}
A.c6.prototype={
i(a){var s=this.a
if(s!=null)return"Assertion failed: "+A.ch(s)
return"Assertion failed"}}
A.a9.prototype={}
A.a4.prototype={
ga8(){return"Invalid argument"+(!this.a?"(s)":"")},
ga7(){return""},
i(a){var s=this,r=s.c,q=r==null?"":" ("+r+")",p=s.d,o=p==null?"":": "+p,n=s.ga8()+q+o
if(!s.a)return n
return n+s.ga7()+": "+A.ch(s.gan())},
gan(){return this.b}}
A.bw.prototype={
gan(){return A.fR(this.b)},
ga8(){return"RangeError"},
ga7(){var s,r=this.e,q=this.f
if(r==null)s=q!=null?": Not less than or equal to "+A.j(q):""
else if(q==null)s=": Not greater than or equal to "+A.j(r)
else if(q>r)s=": Not in inclusive range "+A.j(r)+".."+A.j(q)
else s=q<r?": Valid value range is empty":": Only valid value is "+A.j(r)
return s}}
A.cj.prototype={
gan(){return A.F(this.b)},
ga8(){return"RangeError"},
ga7(){if(A.F(this.b)<0)return": index must not be negative"
var s=this.f
if(s===0)return": no indices are valid"
return": index should be less than "+s},
gp(a){return this.f}}
A.bD.prototype={
i(a){return"Unsupported operation: "+this.a}}
A.cA.prototype={
i(a){return"UnimplementedError: "+this.a}}
A.au.prototype={
i(a){return"Bad state: "+this.a}}
A.cd.prototype={
i(a){var s=this.a
if(s==null)return"Concurrent modification during iteration."
return"Concurrent modification during iteration: "+A.ch(s)+"."}}
A.cr.prototype={
i(a){return"Out of Memory"},
gJ(){return null},
$in:1}
A.bz.prototype={
i(a){return"Stack Overflow"},
gJ(){return null},
$in:1}
A.dH.prototype={
i(a){return"Exception: "+this.a}}
A.ci.prototype={
i(a){var s=this.a,r=""!==s?"FormatException: "+s:"FormatException"
return r}}
A.d.prototype={
gp(a){var s,r=this.gu(this)
for(s=0;r.n();)++s
return s},
aX(a,b){var s,r
A.hN(b,"index")
s=this.gu(this)
for(r=b;s.n();){if(r===0)return s.gq();--r}throw A.b(A.fj(b,b-r,this,"index"))},
i(a){return A.hH(this,"(",")")}}
A.E.prototype={
i(a){return"MapEntry("+A.j(this.a)+": "+A.j(this.b)+")"}}
A.t.prototype={
gl(a){return A.c.prototype.gl.call(this,0)},
i(a){return"null"}}
A.c.prototype={$ic:1,
D(a,b){return this===b},
gl(a){return A.bv(this)},
i(a){return"Instance of '"+A.ct(this)+"'"},
gk(a){return A.ha(this)},
toString(){return this.i(this)}}
A.cO.prototype={
i(a){return""},
$ia0:1}
A.aW.prototype={
gp(a){return this.a.length},
i(a){var s=this.a
return s.charCodeAt(0)==0?s:s},
$ihQ:1}
A.dg.prototype={
i(a){return"Promise was rejected with a value of `"+(this.a?"undefined":"null")+"`."}}
A.ew.prototype={
$1(a){return this.a.a_(this.b.h("0/?").a(a))},
$S:4}
A.ex.prototype={
$1(a){if(a==null)return this.a.aW(new A.dg(a===undefined))
return this.a.aW(a)},
$S:4}
A.cC.prototype={
ag(){var s=this.d
this.d=null
if(s!=null&&(s.a.a&30)===0)s.al()},
bk(a){var s,r,q,p,o,n,m,l
if(a==null||typeof a==="undefined")return
s=A.G(a)
try{r=A.F(s.numberOfFrames)
q=A.F(s.numberOfChannels)
p=A.F(s.sampleRate)
o={planeIndex:0,format:"f32"}
n=A.F(s.allocationSize(o))
l=n
if(typeof l!=="number")return l.av()
l=B.j.ae(l,4)
m=new Float32Array(l)
s.copyTo(m,o)
B.a.j(this.b,new A.aG(m,r,p,q,B.j.b5(A.fQ(s.timestamp))))}finally{s.close()
this.ag()}},
T(){var s=0,r=A.X(t.H),q,p=this,o
var $async$T=A.Y(function(a,b){if(a===1)return A.U(b,r)
for(;;)switch(s){case 0:if(p.b.length!==0||p.c!=null){s=1
break}o=new A.e($.f,t.D)
p.d=new A.a6(o,t.h)
s=3
return A.B(o.b4(B.w,new A.du()),$async$T)
case 3:p.d=null
case 1:return A.V(q,r)}})
return A.W($async$T,r)},
X(){var s=this.c
if(s!=null){this.c=null
throw A.b(A.fh("webcodecs",J.aD(s)))}},
B(a){var s=0,r=A.X(t.W),q,p=this,o,n,m,l
var $async$B=A.Y(function(b,c){if(b===1)return A.U(c,r)
for(;;)switch(s){case 0:p.X()
o=p.a
if(o==null)throw A.b(A.a8("WebCodecsAudioDecoder: not open"))
n=v.G.EncodedAudioChunk
m=a.e?"key":"delta"
o.decode(A.G(new n({type:m,timestamp:a.b,data:a.a})))
s=3
return A.B(p.T(),$async$B)
case 3:p.X()
m=p.b
l=A.dc(m,!0,t.R)
B.a.F(m)
q=l
s=1
break
case 1:return A.V(q,r)}})
return A.W($async$B,r)},
C(){var s=0,r=A.X(t.W),q,p=this,o,n,m
var $async$C=A.Y(function(a,b){if(a===1)return A.U(b,r)
for(;;)switch(s){case 0:m=p.a
if(m==null){q=B.X
s=1
break}s=3
return A.B(A.he(A.G(m.flush()),t.X),$async$C)
case 3:p.X()
o=p.b
n=A.dc(o,!0,t.R)
B.a.F(o)
q=n
s=1
break
case 1:return A.V(q,r)}})
return A.W($async$C,r)},
v(){var s=0,r=A.X(t.H),q=this,p,o
var $async$v=A.Y(function(a,b){if(a===1)return A.U(b,r)
for(;;)switch(s){case 0:try{p=q.a
if(p!=null)p.close()}catch(n){}q.a=null
B.a.F(q.b)
q.ag()
return A.V(null,r)}})
return A.W($async$v,r)}}
A.du.prototype={
$0(){},
$S:2}
A.dv.prototype={
$1(a){this.a.bk(a)},
$S:1}
A.dw.prototype={
$1(a){var s=this.a
s.c=a
s.ag()},
$S:1}
A.cD.prototype={
ah(){var s=this.d
this.d=null
if(s!=null&&(s.a.a&30)===0)s.al()},
bl(a){if(a==null||typeof a==="undefined")return
B.a.j(this.b,new A.cE(A.G(a)))
this.ah()},
Y(){var s=0,r=A.X(t.H),q,p=this,o
var $async$Y=A.Y(function(a,b){if(a===1)return A.U(b,r)
for(;;)switch(s){case 0:if(p.b.length!==0||p.c!=null){s=1
break}o=new A.e($.f,t.D)
p.d=new A.a6(o,t.h)
s=3
return A.B(o.b4(B.w,new A.dx()),$async$Y)
case 3:p.d=null
case 1:return A.V(q,r)}})
return A.W($async$Y,r)},
Z(){var s=this.c
if(s!=null){this.c=null
throw A.b(A.fh("webcodecs",J.aD(s)))}},
B(a){var s=0,r=A.X(t.ca),q,p=this,o,n,m
var $async$B=A.Y(function(b,c){if(b===1)return A.U(c,r)
for(;;)switch(s){case 0:p.Z()
o=p.a
if(o==null)throw A.b(A.a8("WebCodecsVideoDecoder: not open"))
n=v.G.EncodedVideoChunk
m=a.e?"key":"delta"
o.decode(A.G(new n({type:m,timestamp:a.b,data:a.a})))
n=p.b
if(n.length!==0){q=B.a.b2(n,0)
s=1
break}s=3
return A.B(p.Y(),$async$B)
case 3:p.Z()
q=n.length===0?null:B.a.b2(n,0)
s=1
break
case 1:return A.V(q,r)}})
return A.W($async$B,r)},
C(){var s=0,r=A.X(t.cW),q,p=this,o,n,m
var $async$C=A.Y(function(a,b){if(a===1)return A.U(b,r)
for(;;)switch(s){case 0:m=p.a
if(m==null){q=B.Y
s=1
break}s=3
return A.B(A.he(A.G(m.flush()),t.X),$async$C)
case 3:p.Z()
o=p.b
n=A.dc(o,!0,t.e)
B.a.F(o)
q=n
s=1
break
case 1:return A.V(q,r)}})
return A.W($async$C,r)},
v(){var s=0,r=A.X(t.H),q=this,p,o,n,m
var $async$v=A.Y(function(a,b){if(a===1)return A.U(b,r)
for(;;)switch(s){case 0:try{p=q.a
if(p!=null)p.close()}catch(l){}q.a=null
for(p=q.b,n=p.length,m=0;m<p.length;p.length===n||(0,A.an)(p),++m)p[m].v()
B.a.F(p)
q.ah()
return A.V(null,r)}})
return A.W($async$v,r)}}
A.dx.prototype={
$0(){},
$S:2}
A.dy.prototype={
$1(a){this.a.bl(a)},
$S:1}
A.dz.prototype={
$1(a){var s=this.a
s.c=a
s.ah()},
$S:1}
A.cE.prototype={
v(){if(this.b)return
this.b=!0
this.a.close()},
$icg:1}
A.en.prototype={
$1(a){var s=0,r=A.X(t.X),q,p=this,o,n,m,l,k,j,i,h,g,f,e
var $async$$1=A.Y(function(b,c){if(b===1)return A.U(c,r)
for(;;)switch(s){case 0:s="open"===a?3:4
break
case 3:o=p.b
case 5:switch(o){case"video":s=7
break
case"audio":s=8
break
default:s=9
break}break
case 7:o=p.c
n=o.m(0,"codec")
n.toString
n=A.fi(B.Z,A.a2(n),t.cq)
m=t.E.a(o.m(0,"extra"))
A.cR(o.m(0,"width"))
A.cR(o.m(0,"height"))
e=p.a
s=10
return A.B(A.eM(new A.d1(n,m,A.h_(o))),$async$$1)
case 10:e.b=c
s=6
break
case 8:o=p.c
n=o.m(0,"codec")
n.toString
e=p.a
s=11
return A.B(A.eL(new A.cY(A.fi(B.a_,A.a2(n),t.w),t.E.a(o.m(0,"extra")),A.cR(o.m(0,"sampleRate")),A.cR(o.m(0,"channels")),A.h_(o))),$async$$1)
case 11:e.a=c
s=6
break
case 9:throw A.b(A.fg("webcodecs-worker","unknown worker role: "+A.j(o)))
case 6:q=null
s=1
break
case 4:l=null
o=!1
if(t.j.b(a)){n=a.length
if(n===2){if(0>=n){q=A.h(a,0)
s=1
break}if("decode"===a[0]){if(1>=n){q=A.h(a,1)
s=1
break}k=a[1]
o=t.I
n=o.b(k)
if(n){o.a(k)
l=k}o=n}}}s=o?12:13
break
case 12:o=l.m(0,"data")
o.toString
t.p.a(o)
n=l.m(0,"pts")
n.toString
A.F(n)
m=l.m(0,"pts")
m.toString
A.F(m)
j=l.m(0,"key")
j.toString
i=new A.d2(o,n,m,A.eQ(j))
o=p.a
n=o.b
s=n!=null?14:15
break
case 14:e=A
s=16
return A.B(n.B(i),$async$$1)
case 16:q=e.h4(c)
s=1
break
case 15:n=[]
s=17
return A.B(o.a.B(i),$async$$1)
case 17:o=c,m=o.length,j=t.N,h=t.X,g=0
case 18:if(!(g<o.length)){s=20
break}f=o[g]
n.push(A.db(["samples",f.a,"frames",f.b,"rate",f.c,"ch",f.d,"pts",f.e],j,h))
case 19:o.length===m||(0,A.an)(o),++g
s=18
break
case 20:q=n
s=1
break
case 13:s="flush"===a?21:22
break
case 21:o=p.a
n=o.b
s=n!=null?23:24
break
case 23:o=[]
s=25
return A.B(n.C(),$async$$1)
case 25:n=c,m=n.length,g=0
case 26:if(!(g<n.length)){s=28
break}o.push(A.h4(n[g]))
case 27:n.length===m||(0,A.an)(n),++g
s=26
break
case 28:q=o
s=1
break
case 24:n=[]
s=29
return A.B(o.a.C(),$async$$1)
case 29:o=c,m=o.length,j=t.N,h=t.X,g=0
case 30:if(!(g<o.length)){s=32
break}f=o[g]
n.push(A.db(["samples",f.a,"frames",f.b,"rate",f.c,"ch",f.d,"pts",f.e],j,h))
case 31:o.length===m||(0,A.an)(o),++g
s=30
break
case 32:q=n
s=1
break
case 22:throw A.b(A.a8("unknown op: "+A.j(a)))
case 1:return A.V(q,r)}})
return A.W($async$$1,r)},
$S:16}
A.N.prototype={
M(){return"VideoCodec."+this.b}}
A.Q.prototype={
M(){return"AudioCodec."+this.b}}
A.d1.prototype={}
A.cY.prototype={}
A.df.prototype={
i(a){return A.ha(this).i(0)+": "+this.a}}
A.d_.prototype={
i(a){return"CodecInitException["+this.b+"]: "+this.a}}
A.cc.prototype={
i(a){return"CodecRuntimeException["+this.b+"]: "+this.a}}
A.d2.prototype={
i(a){var s=this,r=s.e?"KEY":"P/B"
return"EncodedPacket("+s.a.length+"B, pts="+s.b+"us, dts="+s.c+"us, "+r+", track=0)"}}
A.aG.prototype={}
A.ez.prototype={
$1(a){var s,r,q,p,o,n=A.ip(A.G(a).data)
if(n==null)return
r=this.a
q=r.a
if(q!=null){q.bA(n)
return}s=null
try{s=A.f2(n.b,n.d)}catch(p){s=null}o=new A.cQ(A.fw(t.B),new A.a6(new A.e($.f,t.D),t.h))
r.a=o
A.cW(o,this.b,s,B.O).bO(new A.ey(),t.H)},
$S:17}
A.ey.prototype={
$1(a){A.G(v.G.self).close()},
$S:18}
A.cQ.prototype={
G(a){var s,r,q={},p=a.d,o=t.p.b(p),n=o?p.byteLength:0,m=new Uint8Array(12),l=A.fe(m,0,null)
l.$flags&2&&A.ae(l,9)
l.setUint8(0,1)
l.setUint8(1,a.a.c)
l.setUint16(2,a.b,!0)
l.setUint32(4,a.c,!0)
l.setUint32(8,n,!0)
q.h=m
s=A.z([],t.f)
if(p!=null){p=o?p:A.eZ(p,s)
q.p=p}r=A.iX(null,s)
A.G(v.G.self).postMessage(q,r)},
bA(a){var s=this.a,r=s.b
if((r&4)!==0)return
s.j(0,a)},
$ihT:1}
A.el.prototype={
$1(a){var s,r,q
for(s=this.a,r=s.length,q=0;q<r;++q)if(s[q]===a)return
B.a.j(s,a)
this.b[s.length-1]=a},
$S:19}
A.ek.prototype={
$2(a,b){this.a[A.j(a)]=A.eZ(b,this.b)},
$S:3}
A.cv.prototype={
M(){return"SpawnHost."+this.b}}
A.cw.prototype={
M(){return"SpawnPayload."+this.b}}
A.dj.prototype={
b6(){return A.db(["hosted","dart","payload","js","zeroCopyTransfer",!0],t.N,t.X)},
i(a){return"SpawnCaps(hosted: dart, payload: js, zeroCopyTransfer: true)"}}
A.bZ.prototype={
bF(a){var s,r,q
t.k.a(a)
this.e=a
s=this.d
if(s.length===0)return
r=A.fn(s,t.B)
B.a.F(s)
for(s=r.length,q=0;q<r.length;r.length===s||(0,A.an)(r),++q)this.aA(r[q],a)},
bn(a){var s,r,q=this
t.B.a(a)
switch(a.a.a){case 2:s=q.b
if((s.b&4)===0)s.j(0,A.f2(a.b,a.d))
break
case 3:r=q.e
if(r==null)B.a.j(q.d,a)
else q.aA(a,r)
break
case 1:q.ab()
break
case 0:case 4:case 5:break}},
aA(a,b){var s,r,q,p,o,n,m,l,k=this,j={}
t.k.a(b)
j.a=null
try{j.a=A.f2(a.b,a.d)}catch(n){s=A.H(n)
r=A.I(n)
k.W(a.c,s,r)
return}q=A.hZ()
try{m=q
j=A.hG(new A.eb(j,b),t.X)
l=m.b
if(l==null?m!=null:l!==m)A.ad(new A.aK("Local '' has already been initialized."))
m.b=j}catch(n){p=A.H(n)
o=A.I(n)
k.W(a.c,p,o)
return}j=q
m=j.b
if(m==null?j==null:m===j)A.ad(new A.aK("Local '' has not been initialized."))
m.P(new A.ec(k,a),new A.ed(k,a),t.P)},
W(a,b,c){var s,r,q
t.l.a(c)
s=J.ac(b)
r=A.C(s.gk(b).a,null)
s=s.i(b)
q=c.i(0)
this.a.G(new A.J(B.h,0,a,B.i.a1(r+"\n"+A.f6(s,"\n"," ")+"\n"+q)))},
bp(){return this.ab()},
ab(){var s,r=this
if(r.f)return
r.f=!0
s=r.c
if((s.a.a&30)===0)s.al()
r.bh()
s=r.b
if((s.b&4)===0)s.v()},
bh(){var s,r,q,p,o,n,m,l=this.d
if(l.length===0)return
s=A.fn(l,t.B)
B.a.F(l)
for(l=s.length,r=this.a,q=0;q<s.length;s.length===l||(0,A.an)(s),++q){p=s[q]
o=new A.au("spawn: the worker closed without installing a request handler (WorkerChannel.handleRequests was never called)")
n=A.C(o.gk(0).a,null)
o=o.i(0)
m=B.e.i(0)
r.G(new A.J(B.h,0,p.c,B.i.a1(n+"\n"+A.f6(o,"\n"," ")+"\n"+m)))}},
$ieN:1}
A.eb.prototype={
$0(){return this.b.$1(this.a.a)},
$S:21}
A.ec.prototype={
$1(a){var s,r,q,p,o,n,m=this
try{s=null
r=null
q=A.ja(a)
s=q.a
r=q.b
m.a.a.G(new A.J(B.D,s,m.b.c,r))}catch(n){p=A.H(n)
o=A.I(n)
m.a.W(m.b.c,p,o)}},
$S:1}
A.ed.prototype={
$2(a,b){this.a.W(this.b.c,A.T(a),t.l.a(b))},
$S:5}
A.J.prototype={
i(a){var s=this,r=s.a.i(0),q=s.d
return"Frame("+r+", typeId: "+s.b+", correlationId: "+s.c+", payload: "+A.j(t.p.b(q)?""+q.byteLength+" bytes":J.b7(q))+")"}}
A.ei.prototype={
$2(a,b){if(typeof a!="string")throw A.b(A.aE(a,this.a,"spawn map keys must be String, got "+J.b7(a).i(0)))
A.eS(b,this.b,this.a+'["'+a+'"]')},
$S:3}
A.aV.prototype={
i(a){return"PlatformValue("+J.b7(this.a).i(0)+")"}}
A.a5.prototype={
M(){return"WireKind."+this.b}}
A.cF.prototype={
i(a){var s=this
return"WireHeader(v"+s.a+", "+s.b.i(0)+", typeId: "+s.c+", correlationId: "+s.d+", payloadLength: "+s.e+")"},
D(a,b){var s=this
if(b==null)return!1
return b instanceof A.cF&&b.a===s.a&&b.b===s.b&&b.c===s.c&&b.d===s.d&&b.e===s.e},
gl(a){var s=this
return A.fo(s.a,s.b,s.c,s.d,s.e)}}
A.dA.prototype={
bz(a,b){var s
this.a.m(0,a)
s=A.a8("spawn: no WireMessage decoder registered for typeId "+a+". Both ends must call the same WireRegistry.instance.register(...).")
throw A.b(s)}};(function aliases(){var s=J.ag.prototype
s.ba=s.i})();(function installTearOffs(){var s=hunkHelpers._static_1,r=hunkHelpers._static_0,q=hunkHelpers._static_2,p=hunkHelpers._instance_2u,o=hunkHelpers._instance_1u,n=hunkHelpers._instance_0u
s(A,"j_","hV",6)
s(A,"j0","hW",6)
s(A,"j1","hX",6)
r(A,"h6","iU",0)
q(A,"j2","iN",9)
p(A.e.prototype,"gbd","be",9)
s(A,"j7","iq",7)
s(A,"j5","c3",22)
var m
o(m=A.bZ.prototype,"gbm","bn",20)
n(m,"gbo","bp",0)})();(function inheritance(){var s=hunkHelpers.mixin,r=hunkHelpers.inherit,q=hunkHelpers.inheritMany
r(A.c,null)
q(A.c,[A.eE,J.ck,A.by,J.b8,A.n,A.af,A.di,A.d,A.bo,A.bq,A.D,A.az,A.ba,A.bJ,A.dn,A.dh,A.bf,A.bP,A.bp,A.da,A.aq,A.bm,A.dG,A.cP,A.a_,A.cL,A.e7,A.e5,A.bF,A.bT,A.x,A.bH,A.ab,A.e,A.cG,A.bA,A.bQ,A.cH,A.bG,A.aj,A.cI,A.a1,A.cN,A.c_,A.r,A.cb,A.cf,A.dZ,A.e9,A.bc,A.cJ,A.cr,A.bz,A.dH,A.ci,A.E,A.t,A.cO,A.aW,A.dg,A.cC,A.cD,A.cE,A.d1,A.cY,A.df,A.d2,A.aG,A.cQ,A.dj,A.bZ,A.J,A.aV,A.cF,A.dA])
q(J.ck,[J.cm,J.bh,J.bj,J.aI,J.aJ,J.bi,J.aH])
q(J.bj,[J.ag,J.p,A.ah,A.bt])
q(J.ag,[J.cs,J.bC,J.a7])
r(J.cl,A.by)
r(J.d8,J.p)
q(J.bi,[J.bg,J.cn])
q(A.n,[A.aK,A.a9,A.co,A.cB,A.cu,A.cK,A.bk,A.c6,A.a4,A.bD,A.cA,A.au,A.cd])
q(A.af,[A.c9,A.ca,A.cz,A.eq,A.es,A.dC,A.dB,A.eg,A.dS,A.dV,A.dk,A.dd,A.ew,A.ex,A.dv,A.dw,A.dy,A.dz,A.en,A.ez,A.ey,A.el,A.ec])
q(A.c9,[A.ev,A.dD,A.dE,A.e6,A.dJ,A.dO,A.dN,A.dL,A.dK,A.dR,A.dQ,A.dP,A.dU,A.dl,A.e4,A.e3,A.dF,A.e0,A.e2,A.ej,A.du,A.dx,A.eb])
q(A.d,[A.i,A.as,A.bI,A.b0])
r(A.bd,A.as)
r(A.b_,A.az)
r(A.bO,A.b_)
r(A.bb,A.ba)
r(A.bu,A.a9)
q(A.cz,[A.cx,A.aF])
r(A.ap,A.bp)
q(A.i,[A.bn,A.bl])
q(A.ca,[A.er,A.eh,A.em,A.dT,A.dW,A.de,A.e_,A.ek,A.ed,A.ei])
r(A.aL,A.ah)
q(A.bt,[A.aM,A.aS])
q(A.aS,[A.bK,A.bM])
r(A.bL,A.bK)
r(A.br,A.bL)
r(A.bN,A.bM)
r(A.bs,A.bN)
q(A.br,[A.aN,A.aO])
q(A.bs,[A.aP,A.aQ,A.aR,A.aT,A.aU,A.at,A.ai])
r(A.bU,A.cK)
r(A.a6,A.bH)
r(A.aX,A.bQ)
r(A.bS,A.bA)
r(A.aY,A.bS)
r(A.aZ,A.bG)
r(A.av,A.aj)
r(A.cM,A.c_)
r(A.cq,A.bk)
r(A.cp,A.cb)
q(A.cf,[A.d9,A.dt])
r(A.dY,A.dZ)
q(A.a4,[A.bw,A.cj])
q(A.cJ,[A.N,A.Q,A.cv,A.cw,A.a5])
q(A.df,[A.d_,A.cc])
s(A.bK,A.r)
s(A.bL,A.D)
s(A.bM,A.r)
s(A.bN,A.D)
s(A.aX,A.cH)})()
var v={G:typeof self!="undefined"?self:globalThis,typeUniverse:{eC:new Map(),tR:{},eT:{},tPV:{},sEA:[]},mangledGlobalNames:{a:"int",l:"double",aC:"num",L:"String",cV:"bool",t:"Null",m:"List",c:"Object",ar:"Map",q:"JSObject"},mangledNames:{},types:["~()","t(c?)","t()","~(c?,c?)","~(@)","t(c,a0)","~(~())","@(@)","t(@)","~(c,a0)","A<~>()","@(@,L)","@(L)","t(~())","t(@,a0)","~(a,@)","A<c?>(c?)","t(q)","t(~)","~(c)","~(J)","c?()","A<~>(eN)"],interceptorsByTag:null,leafTags:null,arrayRti:Symbol("$ti"),rttc:{"2;":(a,b)=>c=>c instanceof A.bO&&a.b(c.a)&&b.b(c.b)}}
A.ie(v.typeUniverse,JSON.parse('{"a7":"ag","cs":"ag","bC":"ag","jy":"ah","p":{"m":["1"],"i":["1"],"q":[],"d":["1"]},"cm":{"cV":[],"k":[]},"bh":{"t":[],"k":[]},"bj":{"q":[]},"ag":{"q":[]},"cl":{"by":[]},"d8":{"p":["1"],"m":["1"],"i":["1"],"q":[],"d":["1"]},"b8":{"R":["1"]},"bi":{"l":[],"aC":[]},"bg":{"l":[],"a":[],"aC":[],"k":[]},"cn":{"l":[],"aC":[],"k":[]},"aH":{"L":[],"fp":[],"k":[]},"aK":{"n":[]},"i":{"d":["1"]},"bo":{"R":["1"]},"as":{"d":["2"],"d.E":"2"},"bd":{"as":["1","2"],"i":["2"],"d":["2"],"d.E":"2"},"bq":{"R":["2"]},"bO":{"b_":[],"az":[]},"ba":{"ar":["1","2"]},"bb":{"ba":["1","2"],"ar":["1","2"]},"bI":{"d":["1"],"d.E":"1"},"bJ":{"R":["1"]},"bu":{"a9":[],"n":[]},"co":{"n":[]},"cB":{"n":[]},"bP":{"a0":[]},"af":{"ao":[]},"c9":{"ao":[]},"ca":{"ao":[]},"cz":{"ao":[]},"cx":{"ao":[]},"aF":{"ao":[]},"cu":{"n":[]},"ap":{"bp":["1","2"],"fm":["1","2"],"ar":["1","2"]},"bn":{"i":["1"],"d":["1"],"d.E":"1"},"aq":{"R":["1"]},"bl":{"i":["E<1,2>"],"d":["E<1,2>"],"d.E":"E<1,2>"},"bm":{"R":["E<1,2>"]},"b_":{"az":[]},"ai":{"bB":[],"r":["a"],"m":["a"],"K":["a"],"i":["a"],"q":[],"u":[],"d":["a"],"D":["a"],"k":[],"r.E":"a"},"ah":{"q":[],"b9":[],"k":[]},"aL":{"ah":[],"q":[],"b9":[],"k":[]},"bt":{"q":[],"u":[]},"cP":{"b9":[]},"aM":{"cZ":[],"q":[],"u":[],"k":[]},"aS":{"K":["1"],"q":[],"u":[]},"br":{"r":["l"],"m":["l"],"K":["l"],"i":["l"],"q":[],"u":[],"d":["l"],"D":["l"]},"bs":{"r":["a"],"m":["a"],"K":["a"],"i":["a"],"q":[],"u":[],"d":["a"],"D":["a"]},"aN":{"d3":[],"r":["l"],"m":["l"],"K":["l"],"i":["l"],"q":[],"u":[],"d":["l"],"D":["l"],"k":[],"r.E":"l"},"aO":{"d4":[],"r":["l"],"m":["l"],"K":["l"],"i":["l"],"q":[],"u":[],"d":["l"],"D":["l"],"k":[],"r.E":"l"},"aP":{"d5":[],"r":["a"],"m":["a"],"K":["a"],"i":["a"],"q":[],"u":[],"d":["a"],"D":["a"],"k":[],"r.E":"a"},"aQ":{"d6":[],"r":["a"],"m":["a"],"K":["a"],"i":["a"],"q":[],"u":[],"d":["a"],"D":["a"],"k":[],"r.E":"a"},"aR":{"d7":[],"r":["a"],"m":["a"],"K":["a"],"i":["a"],"q":[],"u":[],"d":["a"],"D":["a"],"k":[],"r.E":"a"},"aT":{"dq":[],"r":["a"],"m":["a"],"K":["a"],"i":["a"],"q":[],"u":[],"d":["a"],"D":["a"],"k":[],"r.E":"a"},"aU":{"dr":[],"r":["a"],"m":["a"],"K":["a"],"i":["a"],"q":[],"u":[],"d":["a"],"D":["a"],"k":[],"r.E":"a"},"at":{"ds":[],"r":["a"],"m":["a"],"K":["a"],"i":["a"],"q":[],"u":[],"d":["a"],"D":["a"],"k":[],"r.E":"a"},"cK":{"n":[]},"bU":{"a9":[],"n":[]},"bF":{"d0":["1"]},"bT":{"R":["1"]},"b0":{"d":["1"],"d.E":"1"},"x":{"n":[]},"bH":{"d0":["1"]},"a6":{"bH":["1"],"d0":["1"]},"e":{"A":["1"]},"bQ":{"fv":["1"],"fH":["1"],"aw":["1"]},"aX":{"cH":["1"],"bQ":["1"],"fv":["1"],"fH":["1"],"aw":["1"]},"aY":{"bS":["1"],"bA":["1"]},"aZ":{"bG":["1"],"cy":["1"],"aw":["1"]},"bG":{"cy":["1"],"aw":["1"]},"bS":{"bA":["1"]},"av":{"aj":["1"]},"cI":{"aj":["@"]},"c_":{"fA":[]},"cM":{"c_":[],"fA":[]},"bp":{"ar":["1","2"]},"bk":{"n":[]},"cq":{"n":[]},"cp":{"cb":["c?","L"]},"l":{"aC":[]},"a":{"aC":[]},"m":{"i":["1"],"d":["1"]},"L":{"fp":[]},"cJ":{"be":[]},"c6":{"n":[]},"a9":{"n":[]},"a4":{"n":[]},"bw":{"n":[]},"cj":{"n":[]},"bD":{"n":[]},"cA":{"n":[]},"au":{"n":[]},"cd":{"n":[]},"cr":{"n":[]},"bz":{"n":[]},"cO":{"a0":[]},"aW":{"hQ":[]},"cE":{"cg":[]},"N":{"be":[]},"Q":{"be":[]},"cQ":{"hT":[]},"cv":{"be":[]},"cw":{"be":[]},"bZ":{"eN":[]},"a5":{"be":[]},"cZ":{"u":[]},"d7":{"m":["a"],"i":["a"],"u":[],"d":["a"]},"bB":{"m":["a"],"i":["a"],"u":[],"d":["a"]},"ds":{"m":["a"],"i":["a"],"u":[],"d":["a"]},"d5":{"m":["a"],"i":["a"],"u":[],"d":["a"]},"dq":{"m":["a"],"i":["a"],"u":[],"d":["a"]},"d6":{"m":["a"],"i":["a"],"u":[],"d":["a"]},"dr":{"m":["a"],"i":["a"],"u":[],"d":["a"]},"d3":{"m":["l"],"i":["l"],"u":[],"d":["l"]},"d4":{"m":["l"],"i":["l"],"u":[],"d":["l"]}}'))
A.id(v.typeUniverse,JSON.parse('{"i":1,"aS":1,"aj":1,"cf":2}'))
var u={c:"Error handler must accept one Object or one Object and a StackTrace as arguments, and return a value of the returned future's type"}
var t=(function rtii(){var s=A.al
return{r:s("@<~>"),n:s("x"),w:s("Q"),J:s("b9"),V:s("cZ"),R:s("aG"),e:s("cg"),x:s("i<@>"),C:s("n"),h4:s("d3"),q:s("d4"),B:s("J"),Z:s("ao"),dQ:s("d5"),an:s("d6"),U:s("d7"),hf:s("d<@>"),A:s("p<aG>"),t:s("p<cg>"),b4:s("p<J>"),f:s("p<c>"),s:s("p<L>"),gn:s("p<@>"),c:s("p<c?>"),T:s("bh"),m:s("q"),g:s("a7"),aU:s("K<@>"),W:s("m<aG>"),cW:s("m<cg>"),j:s("m<@>"),G:s("ar<@,@>"),I:s("ar<L,c?>"),a:s("aL"),gT:s("aM"),al:s("aN"),c2:s("aO"),at:s("aP"),ha:s("aQ"),cv:s("aR"),d:s("aT"),dk:s("aU"),gi:s("at"),Y:s("ai"),P:s("t"),K:s("c"),L:s("jz"),bQ:s("+()"),l:s("a0"),N:s("L"),dm:s("k"),eK:s("a9"),ak:s("u"),h7:s("dq"),bv:s("dr"),go:s("ds"),p:s("bB"),bI:s("bC"),cq:s("N"),g0:s("cC"),dD:s("cD"),h:s("a6<~>"),_:s("e<@>"),fJ:s("e<a>"),D:s("e<~>"),fv:s("bR<c?>"),y:s("cV"),bN:s("cV(c)"),i:s("l"),z:s("@"),O:s("@()"),v:s("@(c)"),Q:s("@(c,a0)"),S:s("a"),ca:s("cg?"),eH:s("A<t>?"),bX:s("q?"),dE:s("ai?"),X:s("c?"),k:s("c?(c?)"),c8:s("L?"),E:s("bB?"),ev:s("aj<@>?"),F:s("ab<@,@>?"),u:s("cV?"),cD:s("l?"),h6:s("a?"),cg:s("aC?"),b:s("~()?"),o:s("aC"),H:s("~"),M:s("~()"),d5:s("~(c)"),da:s("~(c,a0)")}})();(function constants(){var s=hunkHelpers.makeConstList
B.S=J.ck.prototype
B.a=J.p.prototype
B.c=J.bg.prototype
B.j=J.bi.prototype
B.f=J.aH.prototype
B.T=J.a7.prototype
B.U=J.bj.prototype
B.a1=A.ai.prototype
B.x=J.cs.prototype
B.k=J.bC.prototype
B.n=new A.Q(0,"aac")
B.o=new A.Q(1,"opus")
B.p=new A.Q(2,"vorbis")
B.q=new A.Q(3,"mp3")
B.r=new A.Q(4,"flac")
B.t=function getTagFallback(o) {
  var s = Object.prototype.toString.call(o);
  return s.substring(8, s.length - 1);
}
B.G=function() {
  var toStringFunction = Object.prototype.toString;
  function getTag(o) {
    var s = toStringFunction.call(o);
    return s.substring(8, s.length - 1);
  }
  function getUnknownTag(object, tag) {
    if (/^HTML[A-Z].*Element$/.test(tag)) {
      var name = toStringFunction.call(object);
      if (name == "[object Object]") return null;
      return "HTMLElement";
    }
  }
  function getUnknownTagGenericBrowser(object, tag) {
    if (object instanceof HTMLElement) return "HTMLElement";
    return getUnknownTag(object, tag);
  }
  function prototypeForTag(tag) {
    if (typeof window == "undefined") return null;
    if (typeof window[tag] == "undefined") return null;
    var constructor = window[tag];
    if (typeof constructor != "function") return null;
    return constructor.prototype;
  }
  function discriminator(tag) { return null; }
  var isBrowser = typeof HTMLElement == "function";
  return {
    getTag: getTag,
    getUnknownTag: isBrowser ? getUnknownTagGenericBrowser : getUnknownTag,
    prototypeForTag: prototypeForTag,
    discriminator: discriminator };
}
B.L=function(getTagFallback) {
  return function(hooks) {
    if (typeof navigator != "object") return hooks;
    var userAgent = navigator.userAgent;
    if (typeof userAgent != "string") return hooks;
    if (userAgent.indexOf("DumpRenderTree") >= 0) return hooks;
    if (userAgent.indexOf("Chrome") >= 0) {
      function confirm(p) {
        return typeof window == "object" && window[p] && window[p].name == p;
      }
      if (confirm("Window") && confirm("HTMLElement")) return hooks;
    }
    hooks.getTag = getTagFallback;
  };
}
B.H=function(hooks) {
  if (typeof dartExperimentalFixupGetTag != "function") return hooks;
  hooks.getTag = dartExperimentalFixupGetTag(hooks.getTag);
}
B.K=function(hooks) {
  if (typeof navigator != "object") return hooks;
  var userAgent = navigator.userAgent;
  if (typeof userAgent != "string") return hooks;
  if (userAgent.indexOf("Firefox") == -1) return hooks;
  var getTag = hooks.getTag;
  var quickMap = {
    "BeforeUnloadEvent": "Event",
    "DataTransfer": "Clipboard",
    "GeoGeolocation": "Geolocation",
    "Location": "!Location",
    "WorkerMessageEvent": "MessageEvent",
    "XMLDocument": "!Document"};
  function getTagFirefox(o) {
    var tag = getTag(o);
    return quickMap[tag] || tag;
  }
  hooks.getTag = getTagFirefox;
}
B.J=function(hooks) {
  if (typeof navigator != "object") return hooks;
  var userAgent = navigator.userAgent;
  if (typeof userAgent != "string") return hooks;
  if (userAgent.indexOf("Trident/") == -1) return hooks;
  var getTag = hooks.getTag;
  var quickMap = {
    "BeforeUnloadEvent": "Event",
    "DataTransfer": "Clipboard",
    "HTMLDDElement": "HTMLElement",
    "HTMLDTElement": "HTMLElement",
    "HTMLPhraseElement": "HTMLElement",
    "Position": "Geoposition"
  };
  function getTagIE(o) {
    var tag = getTag(o);
    var newTag = quickMap[tag];
    if (newTag) return newTag;
    if (tag == "Object") {
      if (window.DataView && (o instanceof window.DataView)) return "DataView";
    }
    return tag;
  }
  function prototypeForTagIE(tag) {
    var constructor = window[tag];
    if (constructor == null) return null;
    return constructor.prototype;
  }
  hooks.getTag = getTagIE;
  hooks.prototypeForTag = prototypeForTagIE;
}
B.I=function(hooks) {
  var getTag = hooks.getTag;
  var prototypeForTag = hooks.prototypeForTag;
  function getTagFixed(o) {
    var tag = getTag(o);
    if (tag == "Document") {
      if (!!o.xmlVersion) return "!Document";
      return "!HTMLDocument";
    }
    return tag;
  }
  function prototypeForTagFixed(tag) {
    if (tag == "Document") return null;
    return prototypeForTag(tag);
  }
  hooks.getTag = getTagFixed;
  hooks.prototypeForTag = prototypeForTagFixed;
}
B.u=function(hooks) { return hooks; }

B.M=new A.cp()
B.N=new A.cr()
B.d=new A.di()
B.al=new A.cv(0,"dart")
B.am=new A.cw(1,"js")
B.O=new A.dj()
B.i=new A.dt()
B.v=new A.cI()
B.b=new A.cM()
B.e=new A.cO()
B.P=new A.cc("webcodecs-worker","decoder produced a non-browser frame")
B.Q=new A.bc(0)
B.w=new A.bc(2e4)
B.m=new A.a5(1,1,"bye")
B.R=new A.J(B.m,0,0,null)
B.V=new A.d9(null)
B.l=new A.a5(0,0,"hello")
B.aj=new A.a5(2,2,"message")
B.ak=new A.a5(3,3,"request")
B.D=new A.a5(4,4,"response")
B.h=new A.a5(5,5,"error")
B.W=s([B.l,B.m,B.aj,B.ak,B.D,B.h],A.al("p<a5>"))
B.X=s([],t.A)
B.Y=s([],t.t)
B.y=new A.N(0,"h264")
B.z=new A.N(1,"hevc")
B.A=new A.N(2,"av1")
B.B=new A.N(3,"vp9")
B.C=new A.N(4,"vp8")
B.ag=new A.N(5,"mjpeg")
B.ah=new A.N(6,"prores")
B.ai=new A.N(7,"custom")
B.Z=s([B.y,B.z,B.A,B.B,B.C,B.ag,B.ah,B.ai],A.al("p<N>"))
B.E=new A.Q(5,"pcmS16le")
B.F=new A.Q(6,"pcmF32le")
B.a_=s([B.n,B.o,B.p,B.q,B.r,B.E,B.F],A.al("p<Q>"))
B.a2={}
B.a0=new A.bb(B.a2,[],A.al("bb<L,L>"))
B.a3=A.Z("b9")
B.a4=A.Z("cZ")
B.a5=A.Z("d3")
B.a6=A.Z("d4")
B.a7=A.Z("d5")
B.a8=A.Z("d6")
B.a9=A.Z("d7")
B.aa=A.Z("q")
B.ab=A.Z("c")
B.ac=A.Z("dq")
B.ad=A.Z("dr")
B.ae=A.Z("ds")
B.af=A.Z("bB")})();(function staticFields(){$.dX=null
$.O=A.z([],t.f)
$.fq=null
$.fc=null
$.fb=null
$.hb=null
$.h5=null
$.hf=null
$.eo=null
$.et=null
$.f3=null
$.e1=A.z([],A.al("p<m<c>?>"))
$.b1=null
$.c1=null
$.c2=null
$.eV=!1
$.f=B.b})();(function lazyInitializers(){var s=hunkHelpers.lazyFinal
s($,"jw","f7",()=>A.jf("_$dart_dartClosure"))
s($,"jS","hu",()=>B.b.aq(new A.ev(),A.al("A<~>")))
s($,"jP","ht",()=>A.z([new J.cl()],A.al("p<by>")))
s($,"jB","hi",()=>A.aa(A.dp({
toString:function(){return"$receiver$"}})))
s($,"jC","hj",()=>A.aa(A.dp({$method$:null,
toString:function(){return"$receiver$"}})))
s($,"jD","hk",()=>A.aa(A.dp(null)))
s($,"jE","hl",()=>A.aa(function(){var $argumentsExpr$="$arguments$"
try{null.$method$($argumentsExpr$)}catch(r){return r.message}}()))
s($,"jH","ho",()=>A.aa(A.dp(void 0)))
s($,"jI","hp",()=>A.aa(function(){var $argumentsExpr$="$arguments$"
try{(void 0).$method$($argumentsExpr$)}catch(r){return r.message}}()))
s($,"jG","hn",()=>A.aa(A.fy(null)))
s($,"jF","hm",()=>A.aa(function(){try{null.$method$}catch(r){return r.message}}()))
s($,"jK","hr",()=>A.aa(A.fy(void 0)))
s($,"jJ","hq",()=>A.aa(function(){try{(void 0).$method$}catch(r){return r.message}}()))
s($,"jN","f8",()=>A.hU())
s($,"jx","eA",()=>$.hu())
s($,"jO","cX",()=>A.hc(B.ab))
s($,"jM","hs",()=>new A.dA(A.eG(t.S,A.al("jL(bB)"))))})();(function nativeSupport(){!function(){var s=function(a){var m={}
m[a]=1
return Object.keys(hunkHelpers.convertToFastObject(m))[0]}
v.getIsolateTag=function(a){return s("___dart_"+a+v.isolateTag)}
var r="___dart_isolate_tags_"
var q=Object[r]||(Object[r]=Object.create(null))
var p="_ZxYxX"
for(var o=0;;o++){var n=s(p+"_"+o+"_")
if(!(n in q)){q[n]=1
v.isolateTag=n
break}}v.dispatchPropertyName=v.getIsolateTag("dispatch_record")}()
hunkHelpers.setOrUpdateInterceptorsByTag({SharedArrayBuffer:A.ah,ArrayBuffer:A.aL,ArrayBufferView:A.bt,DataView:A.aM,Float32Array:A.aN,Float64Array:A.aO,Int16Array:A.aP,Int32Array:A.aQ,Int8Array:A.aR,Uint16Array:A.aT,Uint32Array:A.aU,Uint8ClampedArray:A.at,CanvasPixelArray:A.at,Uint8Array:A.ai})
hunkHelpers.setOrUpdateLeafTags({SharedArrayBuffer:true,ArrayBuffer:true,ArrayBufferView:false,DataView:true,Float32Array:true,Float64Array:true,Int16Array:true,Int32Array:true,Int8Array:true,Uint16Array:true,Uint32Array:true,Uint8ClampedArray:true,CanvasPixelArray:true,Uint8Array:false})
A.aS.$nativeSuperclassTag="ArrayBufferView"
A.bK.$nativeSuperclassTag="ArrayBufferView"
A.bL.$nativeSuperclassTag="ArrayBufferView"
A.br.$nativeSuperclassTag="ArrayBufferView"
A.bM.$nativeSuperclassTag="ArrayBufferView"
A.bN.$nativeSuperclassTag="ArrayBufferView"
A.bs.$nativeSuperclassTag="ArrayBufferView"})()
Function.prototype.$1=function(a){return this(a)}
Function.prototype.$2=function(a,b){return this(a,b)}
Function.prototype.$0=function(){return this()}
Function.prototype.$3=function(a,b,c){return this(a,b,c)}
Function.prototype.$4=function(a,b,c,d){return this(a,b,c,d)}
Function.prototype.$1$1=function(a){return this(a)}
convertAllToFastObject(w)
convertToFastObject($);(function(a){if(typeof document==="undefined"){a(null)
return}if(typeof document.currentScript!="undefined"){a(document.currentScript)
return}var s=document.scripts
function onLoad(b){for(var q=0;q<s.length;++q){s[q].removeEventListener("load",onLoad,false)}a(b.target)}for(var r=0;r<s.length;++r){s[r].addEventListener("load",onLoad,false)}})(function(a){v.currentScript=a
var s=A.jn
if(typeof dartMainRunner==="function"){dartMainRunner(s,[])}else{s([])}})})()
//# sourceMappingURL=codec_worker.dart.js.map
