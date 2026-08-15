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
if(a[b]!==s){A.kS(b)}a[b]=r}var q=a[b]
a[c]=function(){return q}
return q}}function makeConstList(a,b){if(b!=null)A.f(a,b)
a.$flags=7
return a}function convertToFastObject(a){function t(){}t.prototype=a
new t()
return a}function convertAllToFastObject(a){for(var s=0;s<a.length;++s){convertToFastObject(a[s])}}var y=0
function instanceTearOffGetter(a,b){var s=null
return a?function(c){if(s===null)s=A.fD(b)
return new s(c,this)}:function(){if(s===null)s=A.fD(b)
return new s(this,null)}}function staticTearOffGetter(a){var s=null
return function(){if(s===null)s=A.fD(a).prototype
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
fL(a,b,c,d){return{i:a,p:b,e:c,x:d}},
f3(a){var s,r,q,p,o,n=a[v.dispatchPropertyName]
if(n==null)if($.fI==null){A.kE()
n=a[v.dispatchPropertyName]}if(n!=null){s=n.p
if(!1===s)return n.i
if(!0===s)return a
r=Object.getPrototypeOf(a)
if(s===r)return n.i
if(n.e===r)throw A.b(A.he("Return interceptor for "+A.p(s(a,n))))}q=a.constructor
if(q==null)p=null
else{o=$.es
if(o==null)o=$.es=v.getIsolateTag("_$dart_js")
p=q[o]}if(p!=null)return p
p=A.kI(a)
if(p!=null)return p
if(typeof a=="function")return B.aC
s=Object.getPrototypeOf(a)
if(s==null)return B.R
if(s===Object.prototype)return B.R
if(typeof q=="function"){o=$.es
if(o==null)o=$.es=v.getIsolateTag("_$dart_js")
Object.defineProperty(q,o,{value:B.r,enumerable:false,writable:true,configurable:true})
return B.r}return B.r},
iy(a,b){if(a<0||a>4294967295)throw A.b(A.a4(a,0,4294967295,"length",null))
return J.iz(new Array(a),b)},
iz(a,b){var s=A.f(a,b.h("o<0>"))
s.$flags=1
return s},
as(a){if(typeof a=="number"){if(Math.floor(a)==a)return J.bJ.prototype
return J.cO.prototype}if(typeof a=="string")return J.b7.prototype
if(a==null)return J.bK.prototype
if(typeof a=="boolean")return J.cN.prototype
if(Array.isArray(a))return J.o.prototype
if(typeof a!="object"){if(typeof a=="function")return J.aj.prototype
if(typeof a=="symbol")return J.b9.prototype
if(typeof a=="bigint")return J.b8.prototype
return a}if(a instanceof A.d)return a
return J.f3(a)},
ct(a){if(typeof a=="string")return J.b7.prototype
if(a==null)return a
if(Array.isArray(a))return J.o.prototype
if(typeof a!="object"){if(typeof a=="function")return J.aj.prototype
if(typeof a=="symbol")return J.b9.prototype
if(typeof a=="bigint")return J.b8.prototype
return a}if(a instanceof A.d)return a
return J.f3(a)},
dv(a){if(a==null)return a
if(Array.isArray(a))return J.o.prototype
if(typeof a!="object"){if(typeof a=="function")return J.aj.prototype
if(typeof a=="symbol")return J.b9.prototype
if(typeof a=="bigint")return J.b8.prototype
return a}if(a instanceof A.d)return a
return J.f3(a)},
fG(a){if(a==null)return a
if(typeof a!="object"){if(typeof a=="function")return J.aj.prototype
if(typeof a=="symbol")return J.b9.prototype
if(typeof a=="bigint")return J.b8.prototype
return a}if(a instanceof A.d)return a
return J.f3(a)},
cv(a,b){if(a==null)return b==null
if(typeof a!="object")return b!=null&&a===b
return J.as(a).K(a,b)},
ie(a,b,c){return J.fG(a).bc(a,b,c)},
fd(a,b){return J.fG(a).bd(a,b)},
cw(a,b,c){return J.fG(a).ad(a,b,c)},
ig(a,b){return J.dv(a).V(a,b)},
P(a){return J.as(a).gp(a)},
fe(a){return J.dv(a).gE(a)},
cx(a){return J.ct(a).gk(a)},
bA(a){return J.as(a).gl(a)},
ih(a,b){return J.dv(a).aj(a,b)},
ii(a,b){return J.dv(a).bt(a,b)},
cy(a){return J.as(a).i(a)},
cL:function cL(){},
cN:function cN(){},
bK:function bK(){},
bM:function bM(){},
aw:function aw(){},
cS:function cS(){},
c2:function c2(){},
aj:function aj(){},
b8:function b8(){},
b9:function b9(){},
o:function o(a){this.$ti=a},
cM:function cM(){},
dI:function dI(a){this.$ti=a},
bB:function bB(a,b,c){var _=this
_.a=a
_.b=b
_.c=0
_.d=null
_.$ti=c},
bL:function bL(){},
bJ:function bJ(){},
cO:function cO(){},
b7:function b7(){}},A={fj:function fj(){},
fX(a){return new A.ba("Field '"+a+"' has been assigned during initialization.")},
V(a,b){a=a+b&536870911
a=a+((a&524287)<<10)&536870911
return a^a>>>6},
dZ(a){a=a+((a&67108863)<<3)&536870911
a^=a>>>11
return a+((a&16383)<<15)&536870911},
ds(a,b,c){return a},
fK(a){var s,r
for(s=$.X.length,r=0;r<s;++r)if(a===$.X[r])return!0
return!1},
cZ(a,b,c,d){A.bX(b,"start")
if(c!=null){A.bX(c,"end")
if(b>c)A.n(A.a4(b,0,c,"start",null))}return new A.c1(a,b,c,d.h("c1<0>"))},
fV(){return new A.az("No element")},
d9:function d9(a){this.a=0
this.b=a},
d7:function d7(a){this.a=0
this.b=a},
ba:function ba(a){this.a=a},
cE:function cE(a){this.a=a},
f9:function f9(){},
dV:function dV(){},
bE:function bE(){},
aK:function aK(){},
c1:function c1(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.$ti=d},
aL:function aL(a,b,c){var _=this
_.a=a
_.b=b
_.c=0
_.d=null
_.$ti=c},
bF:function bF(a){this.$ti=a},
bG:function bG(a){this.$ti=a},
N:function N(){},
aS:function aS(){},
bk:function bk(){},
hZ(a){var s=v.mangledGlobalNames[a]
if(s!=null)return s
return"minified:"+a},
li(a,b){var s
if(b!=null){s=b.x
if(s!=null)return s}return t.aU.b(a)},
p(a){var s
if(typeof a=="string")return a
if(typeof a=="number"){if(a!==0)return""+a}else if(!0===a)return"true"
else if(!1===a)return"false"
else if(a==null)return"null"
s=J.cy(a)
return s},
bV(a){var s,r=$.h6
if(r==null)r=$.h6=Symbol("identityHashCode")
s=a[r]
if(s==null){s=Math.random()*0x3fffffff|0
a[r]=s}return s},
cT(a){var s,r,q,p
if(a instanceof A.d)return A.L(A.at(a),null)
s=J.as(a)
if(s===B.aB||s===B.aD||t.bI.b(a)){r=B.y(a)
if(r!=="Object"&&r!=="")return r
q=a.constructor
if(typeof q=="function"){p=q.name
if(typeof p=="string"&&p!=="Object"&&p!=="")return p}}return A.L(A.at(a),null)},
h7(a){var s,r,q
if(a==null||typeof a=="number"||A.dn(a))return J.cy(a)
if(typeof a=="string")return JSON.stringify(a)
if(a instanceof A.av)return a.i(0)
if(a instanceof A.aY)return a.bb(!0)
s=$.ic()
for(r=0;r<1;++r){q=s[r].cs(a)
if(q!=null)return q}return"Instance of '"+A.cT(a)+"'"},
h5(a){var s,r,q,p,o=a.length
if(o<=500)return String.fromCharCode.apply(null,a)
for(s="",r=0;r<o;r=q){q=r+500
p=q<o?q:o
s+=String.fromCharCode.apply(null,a.slice(r,p))}return s},
iN(a){var s,r,q,p=A.f([],t.t)
for(s=a.length,r=0;r<a.length;a.length===s||(0,A.b5)(a),++r){q=a[r]
if(!A.cq(q))throw A.b(A.bx(q))
if(q<=65535)B.a.j(p,q)
else if(q<=1114111){B.a.j(p,55296+(B.b.H(q-65536,10)&1023))
B.a.j(p,56320+(q&1023))}else throw A.b(A.bx(q))}return A.h5(p)},
h8(a){var s,r,q
for(s=a.length,r=0;r<s;++r){q=a[r]
if(!A.cq(q))throw A.b(A.bx(q))
if(q<0)throw A.b(A.bx(q))
if(q>65535)return A.iN(a)}return A.h5(a)},
iO(a,b,c){var s,r,q,p
if(c<=500&&b===0&&c===a.length)return String.fromCharCode.apply(null,a)
for(s=b,r="";s<c;s=q){q=s+500
p=q<c?q:c
r+=String.fromCharCode.apply(null,a.subarray(s,p))}return r},
v(a){var s
if(a<=65535)return String.fromCharCode(a)
if(a<=1114111){s=a-65536
return String.fromCharCode((B.b.H(s,10)|55296)>>>0,s&1023|56320)}throw A.b(A.a4(a,0,1114111,null,null))},
iM(a){var s=a.$thrownJsError
if(s==null)return null
return A.Y(s)},
iP(a,b){var s
if(a.$thrownJsError==null){s=new Error()
A.y(a,s)
a.$thrownJsError=s
s.stack=b.i(0)}},
hU(a){throw A.b(A.bx(a))},
a(a,b){if(a==null)J.cx(a)
throw A.b(A.f1(a,b))},
f1(a,b){var s,r="index"
if(!A.cq(b))return new A.a1(!0,b,r,null)
s=A.aa(J.cx(a))
if(b<0||b>=s)return A.fh(b,s,a,r)
return new A.bW(null,null,!0,b,r,"Value not in range")},
kw(a,b,c){if(a>c)return A.a4(a,0,c,"start",null)
if(b!=null)if(b<a||b>c)return A.a4(b,a,c,"end",null)
return new A.a1(!0,b,"end",null)},
bx(a){return new A.a1(!0,a,null,null)},
b(a){return A.y(a,new Error())},
y(a,b){var s
if(a==null)a=new A.al()
b.dartException=a
s=A.kU
if("defineProperty" in Object){Object.defineProperty(b,"message",{get:s})
b.name=""}else b.toString=s
return b},
kU(){return J.cy(this.dartException)},
n(a,b){throw A.y(a,b==null?new Error():b)},
z(a,b,c){var s
if(b==null)b=0
if(c==null)c=0
s=Error()
A.n(A.jz(a,b,c),s)},
jz(a,b,c){var s,r,q,p,o,n,m,l,k
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
return new A.c3("'"+s+"': Cannot "+o+" "+l+k+n)},
b5(a){throw A.b(A.bD(a))},
am(a){var s,r,q,p,o,n
a=A.hY(a.replace(String({}),"$receiver$"))
s=a.match(/\\\$[a-zA-Z]+\\\$/g)
if(s==null)s=A.f([],t.s)
r=s.indexOf("\\$arguments\\$")
q=s.indexOf("\\$argumentsExpr\\$")
p=s.indexOf("\\$expr\\$")
o=s.indexOf("\\$method\\$")
n=s.indexOf("\\$receiver\\$")
return new A.e_(a.replace(new RegExp("\\\\\\$arguments\\\\\\$","g"),"((?:x|[^x])*)").replace(new RegExp("\\\\\\$argumentsExpr\\\\\\$","g"),"((?:x|[^x])*)").replace(new RegExp("\\\\\\$expr\\\\\\$","g"),"((?:x|[^x])*)").replace(new RegExp("\\\\\\$method\\\\\\$","g"),"((?:x|[^x])*)").replace(new RegExp("\\\\\\$receiver\\\\\\$","g"),"((?:x|[^x])*)"),r,q,p,o,n)},
e0(a){return function($expr$){var $argumentsExpr$="$arguments$"
try{$expr$.$method$($argumentsExpr$)}catch(s){return s.message}}(a)},
hd(a){return function($expr$){try{$expr$.$method$}catch(s){return s.message}}(a)},
fk(a,b){var s=b==null,r=s?null:b.method
return new A.cP(a,r,s?null:b.receiver)},
R(a){var s
if(a==null)return new A.dT(a)
if(a instanceof A.bH){s=a.a
return A.aF(a,s==null?A.ab(s):s)}if(typeof a!=="object")return a
if("dartException" in a)return A.aF(a,a.dartException)
return A.kj(a)},
aF(a,b){if(t.C.b(b))if(b.$thrownJsError==null)b.$thrownJsError=a
return b},
kj(a){var s,r,q,p,o,n,m,l,k,j,i,h,g
if(!("message" in a))return a
s=a.message
if("number" in a&&typeof a.number=="number"){r=a.number
q=r&65535
if((B.b.H(r,16)&8191)===10)switch(q){case 438:return A.aF(a,A.fk(A.p(s)+" (Error "+q+")",null))
case 445:case 5007:A.p(s)
return A.aF(a,new A.bT())}}if(a instanceof TypeError){p=$.i_()
o=$.i0()
n=$.i1()
m=$.i2()
l=$.i5()
k=$.i6()
j=$.i4()
$.i3()
i=$.i8()
h=$.i7()
g=p.G(s)
if(g!=null)return A.aF(a,A.fk(A.aq(s),g))
else{g=o.G(s)
if(g!=null){g.method="call"
return A.aF(a,A.fk(A.aq(s),g))}else if(n.G(s)!=null||m.G(s)!=null||l.G(s)!=null||k.G(s)!=null||j.G(s)!=null||m.G(s)!=null||i.G(s)!=null||h.G(s)!=null){A.aq(s)
return A.aF(a,new A.bT())}}return A.aF(a,new A.d2(typeof s=="string"?s:""))}if(a instanceof RangeError){if(typeof s=="string"&&s.indexOf("call stack")!==-1)return new A.c_()
s=function(b){try{return String(b)}catch(f){}return null}(a)
return A.aF(a,new A.a1(!1,null,null,typeof s=="string"?s.replace(/^RangeError:\s*/,""):s))}if(typeof InternalError=="function"&&a instanceof InternalError)if(typeof s=="string"&&s==="too much recursion")return new A.c_()
return a},
Y(a){var s
if(a instanceof A.bH)return a.b
if(a==null)return new A.ce(a)
s=a.$cachedTrace
if(s!=null)return s
s=new A.ce(a)
if(typeof a==="object")a.$cachedTrace=s
return s},
hV(a){if(a==null)return J.P(a)
if(typeof a=="object")return A.bV(a)
return J.P(a)},
kA(a,b){var s,r,q,p=a.length
for(s=0;s<p;s=q){r=s+1
q=r+1
b.q(0,a[s],a[r])}return b},
jI(a,b,c,d,e,f){t.Z.a(a)
switch(A.aa(b)){case 0:return a.$0()
case 1:return a.$1(c)
case 2:return a.$2(c,d)
case 3:return a.$3(c,d,e)
case 4:return a.$4(c,d,e,f)}throw A.b(new A.eh("Unsupported number of arguments for wrapped closure"))},
dt(a,b){var s=a.$identity
if(!!s)return s
s=A.kp(a,b)
a.$identity=s
return s},
kp(a,b){var s
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
return function(c,d,e){return function(f,g,h,i){return e(c,d,f,g,h,i)}}(a,b,A.jI)},
iq(a2){var s,r,q,p,o,n,m,l,k,j,i=a2.co,h=a2.iS,g=a2.iI,f=a2.nDA,e=a2.aI,d=a2.fs,c=a2.cs,b=d[0],a=c[0],a0=i[b],a1=a2.fT
a1.toString
s=h?Object.create(new A.cX().constructor.prototype):Object.create(new A.b6(null,null).constructor.prototype)
s.$initialize=s.constructor
r=h?function static_tear_off(){this.$initialize()}:function tear_off(a3,a4){this.$initialize(a3,a4)}
s.constructor=r
r.prototype=s
s.$_name=b
s.$_target=a0
q=!h
if(q)p=A.fU(b,a0,g,f)
else{s.$static_name=b
p=a0}s.$S=A.il(a1,h,g)
s[a]=p
for(o=p,n=1;n<d.length;++n){m=d[n]
if(typeof m=="string"){l=i[m]
k=m
m=l}else k=""
j=c[n]
if(j!=null){if(q)m=A.fU(k,m,g,f)
s[j]=m}if(n===e)o=m}s.$C=o
s.$R=a2.rC
s.$D=a2.dV
return r},
il(a,b,c){if(typeof a=="number")return a
if(typeof a=="string"){if(b)throw A.b("Cannot compute signature for static tearoff.")
return function(d,e){return function(){return e(this,d)}}(a,A.ij)}throw A.b("Error in functionType of tearoff")},
im(a,b,c,d){var s=A.fT
switch(b?-1:a){case 0:return function(e,f){return function(){return f(this)[e]()}}(c,s)
case 1:return function(e,f){return function(g){return f(this)[e](g)}}(c,s)
case 2:return function(e,f){return function(g,h){return f(this)[e](g,h)}}(c,s)
case 3:return function(e,f){return function(g,h,i){return f(this)[e](g,h,i)}}(c,s)
case 4:return function(e,f){return function(g,h,i,j){return f(this)[e](g,h,i,j)}}(c,s)
case 5:return function(e,f){return function(g,h,i,j,k){return f(this)[e](g,h,i,j,k)}}(c,s)
default:return function(e,f){return function(){return e.apply(f(this),arguments)}}(d,s)}},
fU(a,b,c,d){if(c)return A.ip(a,b,d)
return A.im(b.length,d,a,b)},
io(a,b,c,d){var s=A.fT,r=A.ik
switch(b?-1:a){case 0:throw A.b(new A.cU("Intercepted function with no arguments."))
case 1:return function(e,f,g){return function(){return f(this)[e](g(this))}}(c,r,s)
case 2:return function(e,f,g){return function(h){return f(this)[e](g(this),h)}}(c,r,s)
case 3:return function(e,f,g){return function(h,i){return f(this)[e](g(this),h,i)}}(c,r,s)
case 4:return function(e,f,g){return function(h,i,j){return f(this)[e](g(this),h,i,j)}}(c,r,s)
case 5:return function(e,f,g){return function(h,i,j,k){return f(this)[e](g(this),h,i,j,k)}}(c,r,s)
case 6:return function(e,f,g){return function(h,i,j,k,l){return f(this)[e](g(this),h,i,j,k,l)}}(c,r,s)
default:return function(e,f,g){return function(){var q=[g(this)]
Array.prototype.push.apply(q,arguments)
return e.apply(f(this),q)}}(d,r,s)}},
ip(a,b,c){var s,r
if($.fR==null)$.fR=A.fQ("interceptor")
if($.fS==null)$.fS=A.fQ("receiver")
s=b.length
r=A.io(s,c,a,b)
return r},
fD(a){return A.iq(a)},
ij(a,b){return A.cm(v.typeUniverse,A.at(a.a),b)},
fT(a){return a.a},
ik(a){return a.b},
fQ(a){var s,r,q,p=new A.b6("receiver","interceptor"),o=Object.getOwnPropertyNames(p)
o.$flags=1
s=o
for(o=s.length,r=0;r<o;++r){q=s[r]
if(p[q]===a)return q}throw A.b(A.cz("Field name "+a+" not found.",null))},
kB(a){return v.getIsolateTag(a)},
lh(a,b,c){Object.defineProperty(a,b,{value:c,enumerable:false,writable:true,configurable:true})},
kI(a){var s,r,q,p,o,n=A.aq($.hT.$1(a)),m=$.f2[n]
if(m!=null){Object.defineProperty(a,v.dispatchPropertyName,{value:m,enumerable:false,writable:true,configurable:true})
return m.i}s=$.f7[n]
if(s!=null)return s
r=v.interceptorsByTag[n]
if(r==null){q=A.eP($.hR.$2(a,n))
if(q!=null){m=$.f2[q]
if(m!=null){Object.defineProperty(a,v.dispatchPropertyName,{value:m,enumerable:false,writable:true,configurable:true})
return m.i}s=$.f7[q]
if(s!=null)return s
r=v.interceptorsByTag[q]
n=q}}if(r==null)return null
s=r.prototype
p=n[0]
if(p==="!"){m=A.f8(s)
$.f2[n]=m
Object.defineProperty(a,v.dispatchPropertyName,{value:m,enumerable:false,writable:true,configurable:true})
return m.i}if(p==="~"){$.f7[n]=s
return s}if(p==="-"){o=A.f8(s)
Object.defineProperty(Object.getPrototypeOf(a),v.dispatchPropertyName,{value:o,enumerable:false,writable:true,configurable:true})
return o.i}if(p==="+")return A.hW(a,s)
if(p==="*")throw A.b(A.he(n))
if(v.leafTags[n]===true){o=A.f8(s)
Object.defineProperty(Object.getPrototypeOf(a),v.dispatchPropertyName,{value:o,enumerable:false,writable:true,configurable:true})
return o.i}else return A.hW(a,s)},
hW(a,b){var s=Object.getPrototypeOf(a)
Object.defineProperty(s,v.dispatchPropertyName,{value:J.fL(b,s,null,null),enumerable:false,writable:true,configurable:true})
return b},
f8(a){return J.fL(a,!1,null,!!a.$iT)},
kK(a,b,c){var s=b.prototype
if(v.leafTags[a]===true)return A.f8(s)
else return J.fL(s,c,null,null)},
kE(){if(!0===$.fI)return
$.fI=!0
A.kF()},
kF(){var s,r,q,p,o,n,m,l
$.f2=Object.create(null)
$.f7=Object.create(null)
A.kD()
s=v.interceptorsByTag
r=Object.getOwnPropertyNames(s)
if(typeof window!="undefined"){window
q=function(){}
for(p=0;p<r.length;++p){o=r[p]
n=$.hX.$1(o)
if(n!=null){m=A.kK(o,s[o],n)
if(m!=null){Object.defineProperty(n,v.dispatchPropertyName,{value:m,enumerable:false,writable:true,configurable:true})
q.prototype=n}}}}for(p=0;p<r.length;++p){o=r[p]
if(/^[A-Za-z_]/.test(o)){l=s[o]
s["!"+o]=l
s["~"+o]=l
s["-"+o]=l
s["+"+o]=l
s["*"+o]=l}}},
kD(){var s,r,q,p,o,n,m=B.a3()
m=A.bw(B.a4,A.bw(B.a5,A.bw(B.z,A.bw(B.z,A.bw(B.a6,A.bw(B.a7,A.bw(B.a8(B.y),m)))))))
if(typeof dartNativeDispatchHooksTransformer!="undefined"){s=dartNativeDispatchHooksTransformer
if(typeof s=="function")s=[s]
if(Array.isArray(s))for(r=0;r<s.length;++r){q=s[r]
if(typeof q=="function")m=q(m)||m}}p=m.getTag
o=m.getUnknownTag
n=m.prototypeForTag
$.hT=new A.f4(p)
$.hR=new A.f5(o)
$.hX=new A.f6(n)},
bw(a,b){return a(b)||b},
kr(a,b){var s=b.length,r=v.rttc[""+s+";"+a]
if(r==null)return null
if(s===0)return r
if(s===r.length)return r.apply(null,b)
return r(b)},
ky(a){if(a.indexOf("$",0)>=0)return a.replace(/\$/g,"$$$$")
return a},
hY(a){if(/[[\]{}()*+?.\\^$|]/.test(a))return a.replace(/[[\]{}()*+?.\\^$|]/g,"\\$&")
return a},
fM(a,b,c){var s=A.kR(a,b,c)
return s},
kR(a,b,c){var s,r,q
if(b===""){if(a==="")return c
s=a.length
for(r=c,q=0;q<s;++q)r=r+a[q]+c
return r.charCodeAt(0)==0?r:r}if(a.indexOf(b,0)<0)return a
if(a.length<500||c.indexOf("$",0)>=0)return a.split(b).join(c)
return a.replace(new RegExp(A.hY(b),"g"),A.ky(c))},
bq:function bq(a,b){this.a=a
this.b=b},
bZ:function bZ(){},
e_:function e_(a,b,c,d,e,f){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f},
bT:function bT(){},
cP:function cP(a,b,c){this.a=a
this.b=b
this.c=c},
d2:function d2(a){this.a=a},
dT:function dT(a){this.a=a},
bH:function bH(a,b){this.a=a
this.b=b},
ce:function ce(a){this.a=a
this.b=null},
av:function av(){},
cC:function cC(){},
cD:function cD(){},
d_:function d_(){},
cX:function cX(){},
b6:function b6(a,b){this.a=a
this.b=b},
cU:function cU(a){this.a=a},
aJ:function aJ(a){var _=this
_.a=0
_.f=_.e=_.d=_.c=_.b=null
_.r=0
_.$ti=a},
dK:function dK(a,b){this.a=a
this.b=b
this.c=null},
bP:function bP(a,b){this.a=a
this.$ti=b},
bO:function bO(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=null
_.$ti=d},
f4:function f4(a){this.a=a},
f5:function f5(a){this.a=a},
f6:function f6(a){this.a=a},
aY:function aY(){},
bp:function bp(){},
kS(a){throw A.y(A.fX(a),new Error())},
kT(){throw A.y(A.fX(""),new Error())},
j2(){var s=new A.ef()
return s.b=s},
ef:function ef(){this.b=null},
eU(a,b,c){},
K(a){return a},
iI(a,b,c){var s
A.eU(a,b,c)
s=new DataView(a,b,c)
return s},
h2(a){return new Uint8Array(a)},
iJ(a,b,c){A.eU(a,b,c)
return c==null?new Uint8Array(a,b):new Uint8Array(a,b,c)},
ar(a,b,c){if(a>>>0!==a||a>=c)throw A.b(A.f1(b,a))},
aD(a,b,c){var s
if(!(a>>>0!==a))s=b>>>0!==b||a>b||b>c
else s=!0
if(s)throw A.b(A.kw(a,b,c))
return b},
ax:function ax(){},
bb:function bb(){},
bS:function bS(){},
dk:function dk(a){this.a=a},
aN:function aN(){},
C:function C(){},
bR:function bR(){},
U:function U(){},
bc:function bc(){},
bd:function bd(){},
be:function be(){},
bf:function bf(){},
bg:function bg(){},
bh:function bh(){},
bi:function bi(){},
aO:function aO(){},
ay:function ay(){},
c9:function c9(){},
ca:function ca(){},
cb:function cb(){},
cc:function cc(){},
fm(a,b){var s=b.c
return s==null?b.c=A.ck(a,"O",[b.x]):s},
h9(a){var s=a.w
if(s===6||s===7)return A.h9(a.x)
return s===11||s===12},
iQ(a){return a.as},
aE(a){return A.eF(v.typeUniverse,a,!1)},
b0(a1,a2,a3,a4){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0=a2.w
switch(a0){case 5:case 1:case 2:case 3:case 4:return a2
case 6:s=a2.x
r=A.b0(a1,s,a3,a4)
if(r===s)return a2
return A.hr(a1,r,!0)
case 7:s=a2.x
r=A.b0(a1,s,a3,a4)
if(r===s)return a2
return A.hq(a1,r,!0)
case 8:q=a2.y
p=A.bv(a1,q,a3,a4)
if(p===q)return a2
return A.ck(a1,a2.x,p)
case 9:o=a2.x
n=A.b0(a1,o,a3,a4)
m=a2.y
l=A.bv(a1,m,a3,a4)
if(n===o&&l===m)return a2
return A.fs(a1,n,l)
case 10:k=a2.x
j=a2.y
i=A.bv(a1,j,a3,a4)
if(i===j)return a2
return A.hs(a1,k,i)
case 11:h=a2.x
g=A.b0(a1,h,a3,a4)
f=a2.y
e=A.kf(a1,f,a3,a4)
if(g===h&&e===f)return a2
return A.hp(a1,g,e)
case 12:d=a2.y
a4+=d.length
c=A.bv(a1,d,a3,a4)
o=a2.x
n=A.b0(a1,o,a3,a4)
if(c===d&&n===o)return a2
return A.ft(a1,n,c,!0)
case 13:b=a2.x
if(b<a4)return a2
a=a3[b-a4]
if(a==null)return a2
return a
default:throw A.b(A.cB("Attempted to substitute unexpected RTI kind "+a0))}},
bv(a,b,c,d){var s,r,q,p,o=b.length,n=A.eK(o)
for(s=!1,r=0;r<o;++r){q=b[r]
p=A.b0(a,q,c,d)
if(p!==q)s=!0
n[r]=p}return s?n:b},
kg(a,b,c,d){var s,r,q,p,o,n,m=b.length,l=A.eK(m)
for(s=!1,r=0;r<m;r+=3){q=b[r]
p=b[r+1]
o=b[r+2]
n=A.b0(a,o,c,d)
if(n!==o)s=!0
l.splice(r,3,q,p,n)}return s?l:b},
kf(a,b,c,d){var s,r=b.a,q=A.bv(a,r,c,d),p=b.b,o=A.bv(a,p,c,d),n=b.c,m=A.kg(a,n,c,d)
if(q===r&&o===p&&m===n)return b
s=new A.de()
s.a=q
s.b=o
s.c=m
return s},
f(a,b){a[v.arrayRti]=b
return a},
fE(a){var s=a.$S
if(s!=null){if(typeof s=="number")return A.kC(s)
return a.$S()}return null},
kG(a,b){var s
if(A.h9(b))if(a instanceof A.av){s=A.fE(a)
if(s!=null)return s}return A.at(a)},
at(a){if(a instanceof A.d)return A.B(a)
if(Array.isArray(a))return A.a9(a)
return A.fx(J.as(a))},
a9(a){var s=a[v.arrayRti],r=t.gn
if(s==null)return r
if(s.constructor!==r.constructor)return r
return s},
B(a){var s=a.$ti
return s!=null?s:A.fx(a)},
fx(a){var s=a.constructor,r=s.$ccache
if(r!=null)return r
return A.jG(a,s)},
jG(a,b){var s=a instanceof A.av?Object.getPrototypeOf(Object.getPrototypeOf(a)).constructor:b,r=A.jj(v.typeUniverse,s.name)
b.$ccache=r
return r},
kC(a){var s,r=v.types,q=r[a]
if(typeof q=="string"){s=A.eF(v.typeUniverse,q,!1)
r[a]=s
return s}return q},
fH(a){return A.ac(A.B(a))},
fB(a){var s
if(a instanceof A.aY)return a.b0()
s=a instanceof A.av?A.fE(a):null
if(s!=null)return s
if(t.dm.b(a))return J.bA(a).a
if(Array.isArray(a))return A.a9(a)
return A.at(a)},
ac(a){var s=a.r
return s==null?a.r=new A.eE(a):s},
kz(a,b){var s,r,q=b,p=q.length
if(p===0)return t.bQ
if(0>=p)return A.a(q,0)
s=A.cm(v.typeUniverse,A.fB(q[0]),"@<0>")
for(r=1;r<p;++r){if(!(r<q.length))return A.a(q,r)
s=A.ht(v.typeUniverse,s,A.fB(q[r]))}return A.cm(v.typeUniverse,s,a)},
a0(a){return A.ac(A.eF(v.typeUniverse,a,!1))},
jF(a){var s=this
s.b=A.kd(s)
return s.b(a)},
kd(a){var s,r,q,p,o
if(a===t.K)return A.jP
if(A.b3(a))return A.jU
s=a.w
if(s===6)return A.jD
if(s===1)return A.hJ
if(s===7)return A.jK
r=A.kc(a)
if(r!=null)return r
if(s===8){q=a.x
if(a.y.every(A.b3)){a.f="$i"+q
if(q==="k")return A.jN
if(a===t.m)return A.jM
return A.jT}}else if(s===10){p=A.kr(a.x,a.y)
o=p==null?A.hJ:p
return o==null?A.ab(o):o}return A.jB},
kc(a){if(a.w===8){if(a===t.S)return A.cq
if(a===t.i||a===t.o)return A.jO
if(a===t.N)return A.jS
if(a===t.y)return A.dn}return null},
jE(a){var s=this,r=A.jA
if(A.b3(s))r=A.jr
else if(s===t.K)r=A.ab
else if(A.by(s)){r=A.jC
if(s===t.h6)r=A.jq
else if(s===t.c8)r=A.eP
else if(s===t.fQ)r=A.jo
else if(s===t.cg)r=A.hA
else if(s===t.I)r=A.jp
else if(s===t.bX)r=A.fu}else if(s===t.S)r=A.aa
else if(s===t.N)r=A.aq
else if(s===t.y)r=A.hy
else if(s===t.o)r=A.hz
else if(s===t.i)r=A.dm
else if(s===t.m)r=A.b_
s.a=r
return s.a(a)},
jB(a){var s=this
if(a==null)return A.by(s)
return A.kH(v.typeUniverse,A.kG(a,s),s)},
jD(a){if(a==null)return!0
return this.x.b(a)},
jT(a){var s,r=this
if(a==null)return A.by(r)
s=r.f
if(a instanceof A.d)return!!a[s]
return!!J.as(a)[s]},
jN(a){var s,r=this
if(a==null)return A.by(r)
if(typeof a!="object")return!1
if(Array.isArray(a))return!0
s=r.f
if(a instanceof A.d)return!!a[s]
return!!J.as(a)[s]},
jM(a){var s=this
if(a==null)return!1
if(typeof a=="object"){if(a instanceof A.d)return!!a[s.f]
return!0}if(typeof a=="function")return!0
return!1},
hI(a){if(typeof a=="object"){if(a instanceof A.d)return t.m.b(a)
return!0}if(typeof a=="function")return!0
return!1},
jA(a){var s=this
if(a==null){if(A.by(s))return a}else if(s.b(a))return a
throw A.y(A.hC(a,s),new Error())},
jC(a){var s=this
if(a==null||s.b(a))return a
throw A.y(A.hC(a,s),new Error())},
hC(a,b){return new A.ci("TypeError: "+A.hh(a,A.L(b,null)))},
hh(a,b){return A.cJ(a)+": type '"+A.L(A.fB(a),null)+"' is not a subtype of type '"+b+"'"},
a_(a,b){return new A.ci("TypeError: "+A.hh(a,b))},
jK(a){var s=this
return s.x.b(a)||A.fm(v.typeUniverse,s).b(a)},
jP(a){return a!=null},
ab(a){if(a!=null)return a
throw A.y(A.a_(a,"Object"),new Error())},
jU(a){return!0},
jr(a){return a},
hJ(a){return!1},
dn(a){return!0===a||!1===a},
hy(a){if(!0===a)return!0
if(!1===a)return!1
throw A.y(A.a_(a,"bool"),new Error())},
jo(a){if(!0===a)return!0
if(!1===a)return!1
if(a==null)return a
throw A.y(A.a_(a,"bool?"),new Error())},
dm(a){if(typeof a=="number")return a
throw A.y(A.a_(a,"double"),new Error())},
jp(a){if(typeof a=="number")return a
if(a==null)return a
throw A.y(A.a_(a,"double?"),new Error())},
cq(a){return typeof a=="number"&&Math.floor(a)===a},
aa(a){if(typeof a=="number"&&Math.floor(a)===a)return a
throw A.y(A.a_(a,"int"),new Error())},
jq(a){if(typeof a=="number"&&Math.floor(a)===a)return a
if(a==null)return a
throw A.y(A.a_(a,"int?"),new Error())},
jO(a){return typeof a=="number"},
hz(a){if(typeof a=="number")return a
throw A.y(A.a_(a,"num"),new Error())},
hA(a){if(typeof a=="number")return a
if(a==null)return a
throw A.y(A.a_(a,"num?"),new Error())},
jS(a){return typeof a=="string"},
aq(a){if(typeof a=="string")return a
throw A.y(A.a_(a,"String"),new Error())},
eP(a){if(typeof a=="string")return a
if(a==null)return a
throw A.y(A.a_(a,"String?"),new Error())},
b_(a){if(A.hI(a))return a
throw A.y(A.a_(a,"JSObject"),new Error())},
fu(a){if(a==null)return a
if(A.hI(a))return a
throw A.y(A.a_(a,"JSObject?"),new Error())},
hO(a,b){var s,r,q
for(s="",r="",q=0;q<a.length;++q,r=", ")s+=r+A.L(a[q],b)
return s},
k6(a,b){var s,r,q,p,o,n,m=a.x,l=a.y
if(""===m)return"("+A.hO(l,b)+")"
s=l.length
r=m.split(",")
q=r.length-s
for(p="(",o="",n=0;n<s;++n,o=", "){p+=o
if(q===0)p+="{"
p+=A.L(l[n],b)
if(q>=0)p+=" "+r[q];++q}return p+"})"},
hF(a3,a4,a5){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1=", ",a2=null
if(a5!=null){s=a5.length
if(a4==null)a4=A.f([],t.s)
else a2=a4.length
r=a4.length
for(q=s;q>0;--q)B.a.j(a4,"T"+(r+q))
for(p=t.X,o="<",n="",q=0;q<s;++q,n=a1){m=a4.length
l=m-1-q
if(!(l>=0))return A.a(a4,l)
o=o+n+a4[l]
k=a5[q]
j=k.w
if(!(j===2||j===3||j===4||j===5||k===p))o+=" extends "+A.L(k,a4)}o+=">"}else o=""
p=a3.x
i=a3.y
h=i.a
g=h.length
f=i.b
e=f.length
d=i.c
c=d.length
b=A.L(p,a4)
for(a="",a0="",q=0;q<g;++q,a0=a1)a+=a0+A.L(h[q],a4)
if(e>0){a+=a0+"["
for(a0="",q=0;q<e;++q,a0=a1)a+=a0+A.L(f[q],a4)
a+="]"}if(c>0){a+=a0+"{"
for(a0="",q=0;q<c;q+=3,a0=a1){a+=a0
if(d[q+1])a+="required "
a+=A.L(d[q+2],a4)+" "+d[q]}a+="}"}if(a2!=null){a4.toString
a4.length=a2}return o+"("+a+") => "+b},
L(a,b){var s,r,q,p,o,n,m,l=a.w
if(l===5)return"erased"
if(l===2)return"dynamic"
if(l===3)return"void"
if(l===1)return"Never"
if(l===4)return"any"
if(l===6){s=a.x
r=A.L(s,b)
q=s.w
return(q===11||q===12?"("+r+")":r)+"?"}if(l===7)return"FutureOr<"+A.L(a.x,b)+">"
if(l===8){p=A.ki(a.x)
o=a.y
return o.length>0?p+("<"+A.hO(o,b)+">"):p}if(l===10)return A.k6(a,b)
if(l===11)return A.hF(a,b,null)
if(l===12)return A.hF(a.x,b,a.y)
if(l===13){n=a.x
m=b.length
n=m-1-n
if(!(n>=0&&n<m))return A.a(b,n)
return b[n]}return"?"},
ki(a){var s=v.mangledGlobalNames[a]
if(s!=null)return s
return"minified:"+a},
jk(a,b){var s=a.tR[b]
while(typeof s=="string")s=a.tR[s]
return s},
jj(a,b){var s,r,q,p,o,n=a.eT,m=n[b]
if(m==null)return A.eF(a,b,!1)
else if(typeof m=="number"){s=m
r=A.cl(a,5,"#")
q=A.eK(s)
for(p=0;p<s;++p)q[p]=r
o=A.ck(a,b,q)
n[b]=o
return o}else return m},
ji(a,b){return A.hv(a.tR,b)},
jh(a,b){return A.hv(a.eT,b)},
eF(a,b,c){var s,r=a.eC,q=r.get(b)
if(q!=null)return q
s=A.hl(A.hj(a,null,b,!1))
r.set(b,s)
return s},
cm(a,b,c){var s,r,q=b.z
if(q==null)q=b.z=new Map()
s=q.get(c)
if(s!=null)return s
r=A.hl(A.hj(a,b,c,!0))
q.set(c,r)
return r},
ht(a,b,c){var s,r,q,p=b.Q
if(p==null)p=b.Q=new Map()
s=c.as
r=p.get(s)
if(r!=null)return r
q=A.fs(a,b,c.w===9?c.y:[c])
p.set(s,q)
return q},
aC(a,b){b.a=A.jE
b.b=A.jF
return b},
cl(a,b,c){var s,r,q=a.eC.get(c)
if(q!=null)return q
s=new A.a5(null,null)
s.w=b
s.as=c
r=A.aC(a,s)
a.eC.set(c,r)
return r},
hr(a,b,c){var s,r=b.as+"?",q=a.eC.get(r)
if(q!=null)return q
s=A.jf(a,b,r,c)
a.eC.set(r,s)
return s},
jf(a,b,c,d){var s,r,q
if(d){s=b.w
r=!0
if(!A.b3(b))if(!(b===t.P||b===t.T))if(s!==6)r=s===7&&A.by(b.x)
if(r)return b
else if(s===1)return t.P}q=new A.a5(null,null)
q.w=6
q.x=b
q.as=c
return A.aC(a,q)},
hq(a,b,c){var s,r=b.as+"/",q=a.eC.get(r)
if(q!=null)return q
s=A.jd(a,b,r,c)
a.eC.set(r,s)
return s},
jd(a,b,c,d){var s,r
if(d){s=b.w
if(A.b3(b)||b===t.K)return b
else if(s===1)return A.ck(a,"O",[b])
else if(b===t.P||b===t.T)return t.eH}r=new A.a5(null,null)
r.w=7
r.x=b
r.as=c
return A.aC(a,r)},
jg(a,b){var s,r,q=""+b+"^",p=a.eC.get(q)
if(p!=null)return p
s=new A.a5(null,null)
s.w=13
s.x=b
s.as=q
r=A.aC(a,s)
a.eC.set(q,r)
return r},
cj(a){var s,r,q,p=a.length
for(s="",r="",q=0;q<p;++q,r=",")s+=r+a[q].as
return s},
jc(a){var s,r,q,p,o,n=a.length
for(s="",r="",q=0;q<n;q+=3,r=","){p=a[q]
o=a[q+1]?"!":":"
s+=r+p+o+a[q+2].as}return s},
ck(a,b,c){var s,r,q,p=b
if(c.length>0)p+="<"+A.cj(c)+">"
s=a.eC.get(p)
if(s!=null)return s
r=new A.a5(null,null)
r.w=8
r.x=b
r.y=c
if(c.length>0)r.c=c[0]
r.as=p
q=A.aC(a,r)
a.eC.set(p,q)
return q},
fs(a,b,c){var s,r,q,p,o,n
if(b.w===9){s=b.x
r=b.y.concat(c)}else{r=c
s=b}q=s.as+(";<"+A.cj(r)+">")
p=a.eC.get(q)
if(p!=null)return p
o=new A.a5(null,null)
o.w=9
o.x=s
o.y=r
o.as=q
n=A.aC(a,o)
a.eC.set(q,n)
return n},
hs(a,b,c){var s,r,q="+"+(b+"("+A.cj(c)+")"),p=a.eC.get(q)
if(p!=null)return p
s=new A.a5(null,null)
s.w=10
s.x=b
s.y=c
s.as=q
r=A.aC(a,s)
a.eC.set(q,r)
return r},
hp(a,b,c){var s,r,q,p,o,n=b.as,m=c.a,l=m.length,k=c.b,j=k.length,i=c.c,h=i.length,g="("+A.cj(m)
if(j>0){s=l>0?",":""
g+=s+"["+A.cj(k)+"]"}if(h>0){s=l>0?",":""
g+=s+"{"+A.jc(i)+"}"}r=n+(g+")")
q=a.eC.get(r)
if(q!=null)return q
p=new A.a5(null,null)
p.w=11
p.x=b
p.y=c
p.as=r
o=A.aC(a,p)
a.eC.set(r,o)
return o},
ft(a,b,c,d){var s,r=b.as+("<"+A.cj(c)+">"),q=a.eC.get(r)
if(q!=null)return q
s=A.je(a,b,c,r,d)
a.eC.set(r,s)
return s},
je(a,b,c,d,e){var s,r,q,p,o,n,m,l
if(e){s=c.length
r=A.eK(s)
for(q=0,p=0;p<s;++p){o=c[p]
if(o.w===1){r[p]=o;++q}}if(q>0){n=A.b0(a,b,r,0)
m=A.bv(a,c,r,0)
return A.ft(a,n,m,c!==m)}}l=new A.a5(null,null)
l.w=12
l.x=b
l.y=c
l.as=d
return A.aC(a,l)},
hj(a,b,c,d){return{u:a,e:b,r:c,s:[],p:0,n:d}},
hl(a){var s,r,q,p,o,n,m,l=a.r,k=a.s
for(s=l.length,r=0;r<s;){q=l.charCodeAt(r)
if(q>=48&&q<=57)r=A.j6(r+1,q,l,k)
else if((((q|32)>>>0)-97&65535)<26||q===95||q===36||q===124)r=A.hk(a,r,l,k,!1)
else if(q===46)r=A.hk(a,r,l,k,!0)
else{++r
switch(q){case 44:break
case 58:k.push(!1)
break
case 33:k.push(!0)
break
case 59:k.push(A.aX(a.u,a.e,k.pop()))
break
case 94:k.push(A.jg(a.u,k.pop()))
break
case 35:k.push(A.cl(a.u,5,"#"))
break
case 64:k.push(A.cl(a.u,2,"@"))
break
case 126:k.push(A.cl(a.u,3,"~"))
break
case 60:k.push(a.p)
a.p=k.length
break
case 62:A.j8(a,k)
break
case 38:A.j7(a,k)
break
case 63:p=a.u
k.push(A.hr(p,A.aX(p,a.e,k.pop()),a.n))
break
case 47:p=a.u
k.push(A.hq(p,A.aX(p,a.e,k.pop()),a.n))
break
case 40:k.push(-3)
k.push(a.p)
a.p=k.length
break
case 41:A.j5(a,k)
break
case 91:k.push(a.p)
a.p=k.length
break
case 93:o=k.splice(a.p)
A.hm(a.u,a.e,o)
a.p=k.pop()
k.push(o)
k.push(-1)
break
case 123:k.push(a.p)
a.p=k.length
break
case 125:o=k.splice(a.p)
A.ja(a.u,a.e,o)
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
return A.aX(a.u,a.e,m)},
j6(a,b,c,d){var s,r,q=b-48
for(s=c.length;a<s;++a){r=c.charCodeAt(a)
if(!(r>=48&&r<=57))break
q=q*10+(r-48)}d.push(q)
return a},
hk(a,b,c,d,e){var s,r,q,p,o,n,m=b+1
for(s=c.length;m<s;++m){r=c.charCodeAt(m)
if(r===46){if(e)break
e=!0}else{if(!((((r|32)>>>0)-97&65535)<26||r===95||r===36||r===124))q=r>=48&&r<=57
else q=!0
if(!q)break}}p=c.substring(b,m)
if(e){s=a.u
o=a.e
if(o.w===9)o=o.x
n=A.jk(s,o.x)[p]
if(n==null)A.n('No "'+p+'" in "'+A.iQ(o)+'"')
d.push(A.cm(s,o,n))}else d.push(p)
return m},
j8(a,b){var s,r=a.u,q=A.hi(a,b),p=b.pop()
if(typeof p=="string")b.push(A.ck(r,p,q))
else{s=A.aX(r,a.e,p)
switch(s.w){case 11:b.push(A.ft(r,s,q,a.n))
break
default:b.push(A.fs(r,s,q))
break}}},
j5(a,b){var s,r,q,p=a.u,o=b.pop(),n=null,m=null
if(typeof o=="number")switch(o){case-1:n=b.pop()
break
case-2:m=b.pop()
break
default:b.push(o)
break}else b.push(o)
s=A.hi(a,b)
o=b.pop()
switch(o){case-3:o=b.pop()
if(n==null)n=p.sEA
if(m==null)m=p.sEA
r=A.aX(p,a.e,o)
q=new A.de()
q.a=s
q.b=n
q.c=m
b.push(A.hp(p,r,q))
return
case-4:b.push(A.hs(p,b.pop(),s))
return
default:throw A.b(A.cB("Unexpected state under `()`: "+A.p(o)))}},
j7(a,b){var s=b.pop()
if(0===s){b.push(A.cl(a.u,1,"0&"))
return}if(1===s){b.push(A.cl(a.u,4,"1&"))
return}throw A.b(A.cB("Unexpected extended operation "+A.p(s)))},
hi(a,b){var s=b.splice(a.p)
A.hm(a.u,a.e,s)
a.p=b.pop()
return s},
aX(a,b,c){if(typeof c=="string")return A.ck(a,c,a.sEA)
else if(typeof c=="number"){b.toString
return A.j9(a,b,c)}else return c},
hm(a,b,c){var s,r=c.length
for(s=0;s<r;++s)c[s]=A.aX(a,b,c[s])},
ja(a,b,c){var s,r=c.length
for(s=2;s<r;s+=3)c[s]=A.aX(a,b,c[s])},
j9(a,b,c){var s,r,q=b.w
if(q===9){if(c===0)return b.x
s=b.y
r=s.length
if(c<=r)return s[c-1]
c-=r
b=b.x
q=b.w}else if(c===0)return b
if(q!==8)throw A.b(A.cB("Indexed base must be an interface type"))
s=b.y
if(c<=s.length)return s[c-1]
throw A.b(A.cB("Bad index "+c+" for "+b.i(0)))},
kH(a,b,c){var s,r=b.d
if(r==null)r=b.d=new Map()
s=r.get(c)
if(s==null){s=A.x(a,b,null,c,null)
r.set(c,s)}return s},
x(a,b,c,d,e){var s,r,q,p,o,n,m,l,k,j,i
if(b===d)return!0
if(A.b3(d))return!0
s=b.w
if(s===4)return!0
if(A.b3(b))return!1
if(b.w===1)return!0
r=s===13
if(r)if(A.x(a,c[b.x],c,d,e))return!0
q=d.w
p=t.P
if(b===p||b===t.T){if(q===7)return A.x(a,b,c,d.x,e)
return d===p||d===t.T||q===6}if(d===t.K){if(s===7)return A.x(a,b.x,c,d,e)
return s!==6}if(s===7){if(!A.x(a,b.x,c,d,e))return!1
return A.x(a,A.fm(a,b),c,d,e)}if(s===6)return A.x(a,p,c,d,e)&&A.x(a,b.x,c,d,e)
if(q===7){if(A.x(a,b,c,d.x,e))return!0
return A.x(a,b,c,A.fm(a,d),e)}if(q===6)return A.x(a,b,c,p,e)||A.x(a,b,c,d.x,e)
if(r)return!1
p=s!==11
if((!p||s===12)&&d===t.Z)return!0
o=s===10
if(o&&d===t.gT)return!0
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
if(!A.x(a,j,c,i,e)||!A.x(a,i,e,j,c))return!1}return A.hH(a,b.x,c,d.x,e)}if(q===11){if(b===t.g)return!0
if(p)return!1
return A.hH(a,b,c,d,e)}if(s===8){if(q!==8)return!1
return A.jL(a,b,c,d,e)}if(o&&q===10)return A.jR(a,b,c,d,e)
return!1},
hH(a3,a4,a5,a6,a7){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2
if(!A.x(a3,a4.x,a5,a6.x,a7))return!1
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
if(!A.x(a3,p[h],a7,g,a5))return!1}for(h=0;h<m;++h){g=l[h]
if(!A.x(a3,p[o+h],a7,g,a5))return!1}for(h=0;h<i;++h){g=l[m+h]
if(!A.x(a3,k[h],a7,g,a5))return!1}f=s.c
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
if(!A.x(a3,e[a+2],a7,g,a5))return!1
break}}while(b<d){if(f[b+1])return!1
b+=3}return!0},
jL(a,b,c,d,e){var s,r,q,p,o,n=b.x,m=d.x
while(n!==m){s=a.tR[n]
if(s==null)return!1
if(typeof s=="string"){n=s
continue}r=s[m]
if(r==null)return!1
q=r.length
p=q>0?new Array(q):v.typeUniverse.sEA
for(o=0;o<q;++o)p[o]=A.cm(a,b,r[o])
return A.hx(a,p,null,c,d.y,e)}return A.hx(a,b.y,null,c,d.y,e)},
hx(a,b,c,d,e,f){var s,r=b.length
for(s=0;s<r;++s)if(!A.x(a,b[s],d,e[s],f))return!1
return!0},
jR(a,b,c,d,e){var s,r=b.y,q=d.y,p=r.length
if(p!==q.length)return!1
if(b.x!==d.x)return!1
for(s=0;s<p;++s)if(!A.x(a,r[s],c,q[s],e))return!1
return!0},
by(a){var s=a.w,r=!0
if(!(a===t.P||a===t.T))if(!A.b3(a))if(s!==6)r=s===7&&A.by(a.x)
return r},
b3(a){var s=a.w
return s===2||s===3||s===4||s===5||a===t.X},
hv(a,b){var s,r,q=Object.keys(b),p=q.length
for(s=0;s<p;++s){r=q[s]
a[r]=b[r]}},
eK(a){return a>0?new Array(a):v.typeUniverse.sEA},
a5:function a5(a,b){var _=this
_.a=a
_.b=b
_.r=_.f=_.d=_.c=null
_.w=0
_.as=_.Q=_.z=_.y=_.x=null},
de:function de(){this.c=this.b=this.a=null},
eE:function eE(a){this.a=a},
dd:function dd(){},
ci:function ci(a){this.a=a},
iY(){var s,r,q
if(self.scheduleImmediate!=null)return A.kl()
if(self.MutationObserver!=null&&self.document!=null){s={}
r=self.document.createElement("div")
q=self.document.createElement("span")
s.a=null
new self.MutationObserver(A.dt(new A.eb(s),1)).observe(r,{childList:true})
return new A.ea(s,r,q)}else if(self.setImmediate!=null)return A.km()
return A.kn()},
iZ(a){self.scheduleImmediate(A.dt(new A.ec(t.M.a(a)),0))},
j_(a){self.setImmediate(A.dt(new A.ed(t.M.a(a)),0))},
j0(a){t.M.a(a)
A.jb(0,a)},
jb(a,b){var s=new A.eC()
s.bG(a,b)
return s},
G(a){return new A.c4(new A.j($.i,a.h("j<0>")),a.h("c4<0>"))},
F(a,b){a.$2(0,null)
b.b=!0
return b.a},
cp(a,b){A.ju(a,b)},
E(a,b){b.aD(a)},
D(a,b){b.bh(A.R(a),A.Y(a))},
ju(a,b){var s,r,q=new A.eR(b),p=new A.eS(b)
if(a instanceof A.j)a.ba(q,p,t.z)
else{s=t.z
if(a instanceof A.j)a.ae(q,p,s)
else{r=new A.j($.i,t._)
r.a=8
r.c=a
r.ba(q,p,s)}}},
H(a){var s=function(b,c){return function(d,e){while(true){try{b(d,e)
break}catch(r){e=r
d=c}}}}(a,1)
return $.i.aH(new A.f_(s),t.H,t.S,t.z)},
ho(a,b,c){return 0},
dz(a){var s
if(t.C.b(a)){s=a.gak()
if(s!=null)return s}return B.B},
iv(a,b){var s,r,q,p,o,n,m,l=null
try{l=a.$0()}catch(q){s=A.R(q)
r=A.Y(q)
p=new A.j($.i,b.h("j<0>"))
o=s
n=r
m=A.hG(o,n)
o=new A.M(o,n==null?A.dz(o):n)
p.R(o)
return p}return b.h("O<0>").b(l)?l:A.fp(l,b)},
hG(a,b){if($.i===B.c)return null
return null},
jH(a,b){if($.i!==B.c)A.hG(a,b)
if(t.C.b(a))A.iP(a,b)
return new A.M(a,b)},
fp(a,b){var s=new A.j($.i,b.h("j<0>"))
b.a(a)
s.a=8
s.c=a
return s},
fq(a,b,c){var s,r,q,p,o={},n=o.a=a
for(s=t._;r=n.a,(r&4)!==0;n=a){a=s.a(n.c)
o.a=a}if(n===b){s=A.iR()
b.R(new A.M(new A.a1(!0,n,null,"Cannot complete a future with itself"),s))
return}q=b.a&1
s=n.a=r|q
if((s&24)===0){p=t.F.a(b.c)
b.a=b.a&1|4
b.c=n
n.b6(p)
return}if(!c)if(b.c==null)n=(s&16)===0||q!==0
else n=!1
else n=!0
if(n){p=b.T()
b.a6(o.a)
A.aW(b,p)
return}b.a^=2
A.bt(null,null,b.b,t.M.a(new A.el(o,b)))},
aW(a,b){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d={},c=d.a=a
for(s=t.n,r=t.F;;){q={}
p=c.a
o=(p&16)===0
n=!o
if(b==null){if(n&&(p&1)===0){m=s.a(c.c)
A.dp(m.a,m.b)}return}q.a=b
l=b.a
for(c=b;l!=null;c=l,l=k){c.a=null
A.aW(d.a,c)
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
A.dp(j.a,j.b)
return}g=$.i
if(g!==h)$.i=h
else g=null
c=c.c
if((c&15)===8)new A.ep(q,d,n).$0()
else if(o){if((c&1)!==0)new A.eo(q,j).$0()}else if((c&2)!==0)new A.en(d,q).$0()
if(g!=null)$.i=g
c=q.c
if(c instanceof A.j){p=q.a.$ti
p=p.h("O<2>").b(c)||!p.y[1].b(c)}else p=!1
if(p){f=q.a.b
if((c.a&24)!==0){e=r.a(f.c)
f.c=null
b=f.a9(e)
f.a=c.a&30|f.a&1
f.c=c.c
d.a=c
continue}else A.fq(c,f,!0)
return}}f=q.a.b
e=r.a(f.c)
f.c=null
b=f.a9(e)
c=q.b
p=q.c
if(!c){f.$ti.c.a(p)
f.a=8
f.c=p}else{s.a(p)
f.a=f.a&1|16
f.c=p}d.a=f
c=f}},
k7(a,b){var s
if(t.Q.b(a))return b.aH(a,t.z,t.K,t.l)
s=t.v
if(s.b(a))return s.a(a)
throw A.b(A.au(a,"onError",u.c))},
jW(){var s,r
for(s=$.bs;s!=null;s=$.bs){$.cs=null
r=s.b
$.bs=r
if(r==null)$.cr=null
s.a.$0()}},
ke(){$.fy=!0
try{A.jW()}finally{$.cs=null
$.fy=!1
if($.bs!=null)$.fP().$1(A.hS())}},
hP(a){var s=new A.d4(a),r=$.cr
if(r==null){$.bs=$.cr=s
if(!$.fy)$.fP().$1(A.hS())}else $.cr=r.b=s},
kb(a){var s,r,q,p=$.bs
if(p==null){A.hP(a)
$.cs=$.cr
return}s=new A.d4(a)
r=$.cs
if(r==null){s.b=p
$.bs=$.cs=s}else{q=r.b
s.b=q
$.cs=r.b=s
if(q==null)$.cr=s}},
kQ(a){var s=null,r=$.i
if(B.c===r){A.bt(s,s,B.c,a)
return}A.bt(s,s,r,t.M.a(r.be(a)))},
kZ(a,b){A.ds(a,"stream",t.K)
return new A.di(b.h("di<0>"))},
hb(a){var s=null
return new A.bm(s,s,s,s,a.h("bm<0>"))},
fA(a){return},
j1(a,b){if(b==null)b=A.ko()
if(t.da.b(b))return a.aH(b,t.z,t.K,t.l)
if(t.d5.b(b))return t.v.a(b)
throw A.b(A.cz("handleError callback must take either an Object (the error), or both an Object (the error) and a StackTrace.",null))},
jX(a,b){A.dp(A.ab(a),t.l.a(b))},
dp(a,b){A.kb(new A.eX(a,b))},
hM(a,b,c,d,e){var s,r=$.i
if(r===c)return d.$0()
$.i=c
s=r
try{r=d.$0()
return r}finally{$.i=s}},
hN(a,b,c,d,e,f,g){var s,r=$.i
if(r===c)return d.$1(e)
$.i=c
s=r
try{r=d.$1(e)
return r}finally{$.i=s}},
k9(a,b,c,d,e,f,g,h,i){var s,r=$.i
if(r===c)return d.$2(e,f)
$.i=c
s=r
try{r=d.$2(e,f)
return r}finally{$.i=s}},
bt(a,b,c,d){t.M.a(d)
if(B.c!==c){d=c.be(d)
d=d}A.hP(d)},
eb:function eb(a){this.a=a},
ea:function ea(a,b,c){this.a=a
this.b=b
this.c=c},
ec:function ec(a){this.a=a},
ed:function ed(a){this.a=a},
eC:function eC(){},
eD:function eD(a,b){this.a=a
this.b=b},
c4:function c4(a,b){this.a=a
this.b=!1
this.$ti=b},
eR:function eR(a){this.a=a},
eS:function eS(a){this.a=a},
f_:function f_(a){this.a=a},
A:function A(a,b){var _=this
_.a=a
_.e=_.d=_.c=_.b=null
_.$ti=b},
br:function br(a,b){this.a=a
this.$ti=b},
M:function M(a,b){this.a=a
this.b=b},
c6:function c6(){},
bl:function bl(a,b){this.a=a
this.$ti=b},
ao:function ao(a,b,c,d,e){var _=this
_.a=null
_.b=a
_.c=b
_.d=c
_.e=d
_.$ti=e},
j:function j(a,b){var _=this
_.a=0
_.b=a
_.c=null
_.$ti=b},
ei:function ei(a,b){this.a=a
this.b=b},
em:function em(a,b){this.a=a
this.b=b},
el:function el(a,b){this.a=a
this.b=b},
ek:function ek(a,b){this.a=a
this.b=b},
ej:function ej(a,b){this.a=a
this.b=b},
ep:function ep(a,b,c){this.a=a
this.b=b
this.c=c},
eq:function eq(a,b){this.a=a
this.b=b},
er:function er(a){this.a=a},
eo:function eo(a,b){this.a=a
this.b=b},
en:function en(a,b){this.a=a
this.b=b},
d4:function d4(a){this.a=a
this.b=null},
c0:function c0(){},
dX:function dX(a,b){this.a=a
this.b=b},
dY:function dY(a,b){this.a=a
this.b=b},
cf:function cf(){},
eB:function eB(a){this.a=a},
eA:function eA(a){this.a=a},
d5:function d5(){},
bm:function bm(a,b,c,d,e){var _=this
_.a=null
_.b=0
_.c=null
_.d=a
_.e=b
_.f=c
_.r=d
_.$ti=e},
bn:function bn(a,b){this.a=a
this.$ti=b},
bo:function bo(a,b,c,d,e,f){var _=this
_.w=a
_.a=b
_.c=c
_.d=d
_.e=e
_.r=_.f=null
_.$ti=f},
c5:function c5(){},
ee:function ee(a){this.a=a},
ch:function ch(){},
aB:function aB(){},
aU:function aU(a,b){this.b=a
this.a=null
this.$ti=b},
da:function da(){},
a8:function a8(a){var _=this
_.a=0
_.c=_.b=null
_.$ti=a},
ex:function ex(a,b){this.a=a
this.b=b},
di:function di(a){this.$ti=a},
co:function co(){},
dh:function dh(){},
ez:function ez(a,b){this.a=a
this.b=b},
eX:function eX(a,b){this.a=a
this.b=b},
h_(a,b,c){return b.h("@<0>").C(c).h("fY<1,2>").a(A.kA(a,new A.aJ(b.h("@<0>").C(c).h("aJ<1,2>"))))},
fZ(a,b){return new A.aJ(a.h("@<0>").C(b).h("aJ<1,2>"))},
iA(a){return new A.c7(a.h("c7<0>"))},
fr(){var s=Object.create(null)
s["<non-identifier-key>"]=s
delete s["<non-identifier-key>"]
return s},
h0(a){var s,r
if(A.fK(a))return"{...}"
s=new A.aQ("")
try{r={}
B.a.j($.X,a)
s.a+="{"
r.a=!0
a.W(0,new A.dM(r,s))
s.a+="}"}finally{if(0>=$.X.length)return A.a($.X,-1)
$.X.pop()}r=s.a
return r.charCodeAt(0)==0?r:r},
c7:function c7(a){var _=this
_.a=0
_.f=_.e=_.d=_.c=_.b=null
_.r=0
_.$ti=a},
df:function df(a){this.a=a
this.b=null},
c8:function c8(a,b,c){var _=this
_.a=a
_.b=b
_.d=_.c=null
_.$ti=c},
h:function h(){},
Q:function Q(){},
dM:function dM(a,b){this.a=a
this.b=b},
bj:function bj(){},
cd:function cd(){},
jm(a,b,c){var s,r,q,p,o,n=c-b
if(n<=4096)s=$.ib()
else s=new Uint8Array(n)
for(r=a.length,q=0;q<n;++q){p=b+q
if(!(p<r))return A.a(a,p)
o=a[p]
if((o&255)!==o)o=255
s[q]=o}return s},
jl(a,b,c,d){var s=a?$.ia():$.i9()
if(s==null)return null
if(0===c&&d===b.length)return A.hu(s,b)
return A.hu(s,b.subarray(c,d))},
hu(a,b){var s,r
try{s=a.decode(b)
return s}catch(r){}return null},
fW(a,b,c){return new A.bN(a,b)},
jy(a){return a.bu()},
j3(a,b){return new A.et(a,[],A.kq())},
j4(a,b,c){var s,r=new A.aQ(""),q=A.j3(r,b)
q.ah(a)
s=r.a
return s.charCodeAt(0)==0?s:s},
jn(a){switch(a){case 65:return"Missing extension byte"
case 67:return"Unexpected extension byte"
case 69:return"Invalid UTF-8 byte"
case 71:return"Overlong encoding"
case 73:return"Out of unicode range"
case 75:return"Encoded surrogate"
case 77:return"Unfinished UTF-8 octet sequence"
default:return""}},
eI:function eI(){},
eH:function eH(){},
cF:function cF(){},
cH:function cH(){},
bN:function bN(a,b){this.a=a
this.b=b},
cR:function cR(a,b){this.a=a
this.b=b},
cQ:function cQ(){},
dJ:function dJ(a){this.b=a},
eu:function eu(){},
ev:function ev(a,b){this.a=a
this.b=b},
et:function et(a,b,c){this.c=a
this.a=b
this.b=c},
e6:function e6(){},
eJ:function eJ(a){this.b=0
this.c=a},
e5:function e5(a){this.a=a},
eG:function eG(a){this.a=a
this.b=16
this.c=0},
it(a,b){a=A.y(a,new Error())
if(a==null)a=A.ab(a)
a.stack=b.i(0)
throw a},
aM(a,b,c,d){var s,r=J.iy(a,d)
if(a!==0&&b!=null)for(s=0;s<a;++s)r[s]=b
return r},
iB(a,b,c){var s,r,q=A.f([],c.h("o<0>"))
for(s=a.length,r=0;r<a.length;a.length===s||(0,A.b5)(a),++r)B.a.j(q,c.a(a[r]))
q.$flags=1
return q},
fl(a,b){var s,r
if(Array.isArray(a))return A.f(a.slice(0),b.h("o<0>"))
s=A.f([],b.h("o<0>"))
for(r=J.fe(a);r.n();)B.a.j(s,r.gv())
return s},
fn(a,b,c){var s,r,q,p,o
A.bX(b,"start")
s=c==null
r=!s
if(r){q=c-b
if(q<0)throw A.b(A.a4(c,b,null,"end",null))
if(q===0)return""}if(Array.isArray(a)){p=a
o=p.length
if(s)c=o
return A.h8(b>0||c<o?p.slice(b,c):p)}if(t.Y.b(a))return A.iT(a,b,c)
if(r)a=J.ii(a,c)
if(b>0)a=J.ih(a,b)
s=A.fl(a,t.S)
return A.h8(s)},
iT(a,b,c){var s=a.length
if(b>=s)return""
return A.iO(a,b,c==null||c>s?s:c)},
hc(a,b,c){var s=J.fe(b)
if(!s.n())return a
if(c.length===0){do a+=A.p(s.gv())
while(s.n())}else{a+=A.p(s.gv())
while(s.n())a=a+c+A.p(s.gv())}return a},
iR(){return A.Y(new Error())},
cI(a,b,c){var s,r,q
for(s=a.length,r=0;r<s;++r){q=a[r]
if(q.b===b)return q}throw A.b(A.au(b,"name","No enum value with that name"))},
cJ(a){if(typeof a=="number"||A.dn(a)||a==null)return J.cy(a)
if(typeof a=="string")return JSON.stringify(a)
return A.h7(a)},
iu(a,b){A.ds(a,"error",t.K)
A.ds(b,"stackTrace",t.l)
A.it(a,b)},
cB(a){return new A.cA(a)},
cz(a,b){return new A.a1(!1,null,b,a)},
au(a,b,c){return new A.a1(!0,a,b,c)},
a4(a,b,c,d,e){return new A.bW(b,c,!0,a,d,"Invalid value")},
bY(a,b,c){if(0>a||a>c)throw A.b(A.a4(a,0,c,"start",null))
if(b!=null){if(a>b||b>c)throw A.b(A.a4(b,a,c,"end",null))
return b}return c},
bX(a,b){if(a<0)throw A.b(A.a4(a,0,null,b,null))
return a},
fh(a,b,c,d){return new A.cK(b,!0,a,d,"Index out of range")},
e4(a){return new A.c3(a)},
he(a){return new A.d1(a)},
af(a){return new A.az(a)},
bD(a){return new A.cG(a)},
a3(a,b,c){return new A.bI(a,b,c)},
iw(a,b,c){var s,r
if(A.fK(a)){if(b==="("&&c===")")return"(...)"
return b+"..."+c}s=A.f([],t.s)
B.a.j($.X,a)
try{A.jV(a,s)}finally{if(0>=$.X.length)return A.a($.X,-1)
$.X.pop()}r=A.hc(b,t.hf.a(s),", ")+c
return r.charCodeAt(0)==0?r:r},
fi(a,b,c){var s,r
if(A.fK(a))return b+"..."+c
s=new A.aQ(b)
B.a.j($.X,a)
try{r=s
r.a=A.hc(r.a,a,", ")}finally{if(0>=$.X.length)return A.a($.X,-1)
$.X.pop()}s.a+=c
r=s.a
return r.charCodeAt(0)==0?r:r},
jV(a,b){var s,r,q,p,o,n,m,l=a.gE(a),k=0,j=0
for(;;){if(!(k<80||j<3))break
if(!l.n())return
s=A.p(l.gv())
B.a.j(b,s)
k+=s.length+2;++j}if(!l.n()){if(j<=5)return
if(0>=b.length)return A.a(b,-1)
r=b.pop()
if(0>=b.length)return A.a(b,-1)
q=b.pop()}else{p=l.gv();++j
if(!l.n()){if(j<=4){B.a.j(b,A.p(p))
return}r=A.p(p)
if(0>=b.length)return A.a(b,-1)
q=b.pop()
k+=r.length+2}else{o=l.gv();++j
for(;l.n();p=o,o=n){n=l.gv();++j
if(j>100){for(;;){if(!(k>75&&j>3))break
if(0>=b.length)return A.a(b,-1)
k-=b.pop().length+2;--j}B.a.j(b,"...")
return}}q=A.p(p)
r=A.p(o)
k+=r.length+q.length+4}}if(j>b.length+2){k+=5
m="..."}else m=null
for(;;){if(!(k>80&&b.length>3))break
if(0>=b.length)return A.a(b,-1)
k-=b.pop().length+2
if(m==null){k+=5
m="..."}}if(m!=null)B.a.j(b,m)
B.a.j(b,q)
B.a.j(b,r)},
h3(a,b,c,d,e){var s
if(B.i===c){s=B.b.gp(a)
b=J.P(b)
return A.dZ(A.V(A.V($.dx(),s),b))}if(B.i===d){s=B.b.gp(a)
b=J.P(b)
c=J.P(c)
return A.dZ(A.V(A.V(A.V($.dx(),s),b),c))}if(B.i===e){s=B.b.gp(a)
b=J.P(b)
c=J.P(c)
d=J.P(d)
return A.dZ(A.V(A.V(A.V(A.V($.dx(),s),b),c),d))}s=B.b.gp(a)
b=J.P(b)
c=J.P(c)
d=J.P(d)
e=J.P(e)
e=A.dZ(A.V(A.V(A.V(A.V(A.V($.dx(),s),b),c),d),e))
return e},
dc:function dc(){},
q:function q(){},
cA:function cA(a){this.a=a},
al:function al(){},
a1:function a1(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
bW:function bW(a,b,c,d,e,f){var _=this
_.e=a
_.f=b
_.a=c
_.b=d
_.c=e
_.d=f},
cK:function cK(a,b,c,d,e){var _=this
_.f=a
_.a=b
_.b=c
_.c=d
_.d=e},
c3:function c3(a){this.a=a},
d1:function d1(a){this.a=a},
az:function az(a){this.a=a},
cG:function cG(a){this.a=a},
c_:function c_(){},
eh:function eh(a){this.a=a},
bI:function bI(a,b,c){this.a=a
this.b=b
this.c=c},
e:function e(){},
u:function u(){},
d:function d(){},
dj:function dj(){},
aQ:function aQ(a){this.a=a},
eV(a,b){var s,r,q,p,o,n,m,l,k
if(b+7>a.byteLength)return null
s=a.getUint8(b+1)
if(!(a.getUint8(b)===255&&(s&246)===240))return null
r=(s&1)===1?7:9
q=a.getUint8(b+2)
p=a.getUint8(b+3)
o=a.getUint8(b+4)
n=a.getUint8(b+5)
m=B.b.H(q,2)
l=B.b.H(p,6)
k=((p&3)<<11|o<<3|B.b.H(n,5)&7)>>>0
if(k<r)return null
return new A.e9(k,m&15,(q&1)<<2|l&3,r)},
k8(a,b){var s,r=b+65536,q=a.byteLength
if(r<q)q=r
for(s=b;s+7<=q;++s)if(A.jw(a,s))return s
return-1},
jw(a,b){var s,r,q=A.eV(a,b)
if(q==null)return!1
s=b+q.a
r=a.byteLength
if(s>r)return!1
if(s+7>r)return!0
return A.eV(a,s)!=null},
ff(a){var s=A.cu(a,0),r=a.length,q=0
for(;;){if(!(s>0&&q+s<=r))break
q+=s
s=A.cu(a,q)}if(q>0)for(;;){if(!(q<r&&a[q]===0))break;++q}return q},
e9:function e9(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
dy:function dy(a,b,c,d,e,f){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=0
_.r=!1
_.w=f
_.x=null},
fJ(a,b){return a===255&&(b&224)===224&&(b&24)!==8&&(b&6)===2},
eW(a,b){var s,r,q,p,o,n,m,l,k,j,i,h,g=null,f=a.length
if(b+4>f)return g
s=b+1
if(!(s>=0&&s<f))return A.a(a,s)
r=a[s]
if(!(b>=0&&b<f))return A.a(a,b)
if(!A.fJ(a[b],r))return g
s=b+2
if(!(s<f))return A.a(a,s)
q=a[s]
p=r>>>3&3
o=q>>>4&15
n=q>>>2&3
if(n===3)return g
m=p===3
s=m?B.aM:B.aH
if(!(o<s.length))return A.a(s,o)
l=s[o]
if(l===0)return g
A:{if(3===p){if(!(n<3))return A.a(B.L,n)
s=B.L[n]
break A}if(2===p){if(!(n<3))return A.a(B.K,n)
s=B.K[n]
break A}if(!(n<3))return A.a(B.J,n)
s=B.J[n]
break A}k=l*1000
j=q>>>1&1
i=m?B.b.t(144*k,s)+j:B.b.t(72*k,s)+j
if(i<=4)return g
h=b+3
if(!(h<f))return A.a(a,h)
f=(a[h]>>>6&3)===3?1:2
h=m?1152:576
return new A.ew(p,i,s,f,h,(r&1)===0)},
jJ(a,b){var s,r,q=a.length
if(b+4>q)return!1
if(!(b<q))return A.a(a,b)
s=a[b]
r=b+1
if(!(r<q))return A.a(a,r)
if(!A.fJ(s,a[r]))return!1
s=b+2
if(!(s<q))return A.a(a,s)
s=a[s]
return(s>>>4&15)===0&&(s>>>2&3)!==3},
cu(a,b){var s,r,q,p,o,n,m
if(b<0||b+10>a.length)return 0
s=a.length
if(!(b>=0&&b<s))return A.a(a,b)
r=a[b]
q=b+1
if(!(q<s))return A.a(a,q)
q=a[q]
p=b+2
if(!(p<s))return A.a(a,p)
p=a[p]
if(!(r===73&&q===68&&p===51))return 0
r=b+3
if(!(r<s))return A.a(a,r)
if(a[r]!==255){r=b+4
if(!(r<s))return A.a(a,r)
r=a[r]===255}else r=!0
if(r)return 0
for(o=0,n=6;n<10;++n){r=b+n
if(!(r<s))return A.a(a,r)
r=a[r]
if((r&128)!==0)return 0
o=(o<<7|r)>>>0}r=b+5
if(!(r<s))return A.a(a,r)
m=(a[r]&16)!==0?10:0
return 10+o+m},
dq(a,b){var s,r,q,p=A.cu(a,b)
if(p>0)return p
s=a.length
r=!1
if(b+128===s){if(!(b>=0&&b<s))return A.a(a,b)
if(a[b]===84){q=b+1
if(!(q<s))return A.a(a,q)
if(a[q]===65){r=b+2
if(!(r<s))return A.a(a,r)
r=a[r]===71
s=r}else s=r}else s=r}else s=r
if(s)return 128
return 0},
dr(a,b){var s,r,q,p,o=a.length
if(!(b>=0&&b<o))return A.a(a,b)
s=a[b]
r=b+1
if(!(r<o))return A.a(a,r)
r=a[r]
q=b+2
if(!(q<o))return A.a(a,q)
q=a[q]
p=b+3
if(!(p<o))return A.a(a,p)
return(s<<24|r<<16|q<<8|a[p])>>>0},
hK(a,b,c){var s,r,q=c.length,p=a.length
if(b+q>p)return!1
for(s=0;s<q;++s){r=b+s
if(!(r>=0&&r<p))return A.a(a,r)
if(a[r]!==c.charCodeAt(s))return!1}return!0},
k4(a,b,c){var s,r,q,p,o,n,m
if(c.a===3)s=c.d===1?17:32
else s=c.d===1?9:17
r=c.f?2:0
q=b+4+s+r
for(p=0;p<2;++p){if(!A.hK(a,q,B.aJ[p]))continue
o=q+8
r=a.length
if(o>r)return new A.bQ()
n=A.dr(a,q+4)
if((n&1)!==0&&o+4<=r){A.dr(a,o)
o+=4}if((n&2)!==0&&o+4<=r)A.dr(a,o)
return new A.bQ()}m=b+36
if(A.hK(a,m,"VBRI")&&m+18<=a.length){A.dr(a,m+14)
A.dr(a,m+10)
return new A.bQ()}return null},
iE(a1){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b=A.dq(a1,0),a=a1.length,a0=0
for(;;){if(!(b>0&&a0+b<=a))break
a0+=b
b=A.dq(a1,a0)}s=A.iC(a1,a0)
if(s<0){for(r=a0;r+4<=a;++r)if(A.jJ(a1,r))throw A.b(B.ai)
throw A.b(B.at)}q=A.eW(a1,s)
q.toString
p=A.k4(a1,s,q)==null?s:s+q.b
o=t.t
n=A.f([],o)
m=A.f([],o)
l=A.f([],o)
for(o=q.a,k=q.c,j=p,i=0,h=0;j+4<=a;){g=A.dq(a1,j)
if(g>0){j+=g
continue}f=A.eW(a1,j)
if(f!=null&&f.a===o&&f.c===k){e=f.b
d=j+e
if(d>a)break
B.a.j(n,j)
B.a.j(m,e)
B.a.j(l,i)
i+=f.e
j=d
continue}c=A.iD(a1,j+1,q)
if(c<0)break;++h
j=c}if(n.length===0)throw A.b(B.aj)
return new A.dO(A.f([new A.ad(B.v,k,q.d,null)],t.J),a1,new Uint32Array(A.K(n)),new Uint32Array(A.K(m)),new Uint32Array(A.K(l)),k,q.e)},
iC(a,b){var s,r,q
for(s=a.length,r=b;r+4<=s;++r){q=A.dq(a,r)
if(q>0){r+=q-1
continue}if(A.h1(a,r,null))return r}return-1},
iD(a,b,c){var s,r=b+131072,q=a.length
if(r<q)q=r
for(s=b;s+4<=q;++s){if(A.dq(a,s)>0)return s
if(A.h1(a,s,c))return s}return-1},
h1(a,b,c){var s,r,q,p=A.eW(a,b)
if(p==null)return!1
if(c!=null)s=!(p.a===c.a&&p.c===c.c)
else s=!1
if(s)return!1
r=b+p.b
s=a.length
if(r>s)return!1
if(r+4>s)return!0
q=A.eW(a,r)
return q!=null&&q.a===p.a&&q.c===p.c},
ew:function ew(a,b,c,d,e,f){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f},
bQ:function bQ(){},
dO:function dO(a,b,c,d,e,f,g){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f
_.r=g
_.z=0
_.Q=!1},
iH(a){var s,r,q,p,o,n,m,l,k=A.a2(a,0,null),j=A.b1(k,0,k.byteLength),i=j.$ti
j=new A.A(j.a(),i.h("A<1>"))
i=i.c
for(;;){if(!j.n()){s=null
break}r=j.b
s=r==null?i.a(r):r
if(s.a==="moov")break}if(s==null)throw A.b(B.ao)
q=A.J(k,s,"mvhd")
p=1e6
if(q!=null&&q.b<q.c){j=q.b
i=k.getUint8(j)===1?16:8
o=j+4+i
if(o+4<=q.c){n=k.getUint32(o,!1)
p=n>0?n:1e6}}m=A.f([],t.J)
l=A.f([],t.fx)
for(j=A.b1(k,s.b,s.c),i=j.$ti,j=new A.A(j.a(),i.h("A<1>")),i=i.c;j.n();){r=j.b
if(r==null)r=i.a(r)
if(r.a!=="trak")continue
A.iF(k,a,r,m,l,p)}if(m.length===0)throw A.b(B.ah)
if(l.length===0)throw A.b(B.ae)
B.a.bC(l,new A.dR())
return new A.dP(m,a,l)},
iF(b5,b6,b7,b8,b9,c0){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,b0,b1={},b2=b8.length,b3=A.iG(b5,A.J(b5,b7,"tkhd")),b4=A.J(b5,b7,"mdia")
if(b4==null)return
s=A.J(b5,b4,"mdhd")
b1.a=1e6
if(s!=null){r=s.b
q=b5.getUint8(r)===1?16:8
p=b5.getUint32(r+4+q,!1)
b1.a=p
if(p<=0)b1.a=1e6}o=A.J(b5,b4,"hdlr")
n=o!=null&&A.hE(b5,o.b+8)==="vide"
m=A.J(b5,b4,"minf")
l=m==null?null:A.J(b5,m,"stbl")
if(l==null)return
k=A.J(b5,l,"stsd")
if(k==null)return
j=A.k0(b5,k,n)
if(j==null)return
i=A.k2(b5,A.J(b5,l,"stsz"))
r=i.length
h=A.k3(b5,A.J(b5,l,"stts"),r)
g=A.jZ(b5,A.J(b5,l,"ctts"),r)
f=A.ka(b5,l,i)
e=A.k1(b5,A.J(b5,l,"stss"),r)
d=new A.dQ(b1)
c=A.k_(b5,A.J(b5,b7,"edts"),c0)
q=d.$1(c.b)
if(typeof q!=="number")return A.hU(q)
b=c.a-q
for(q=h.length,a=e==null,a0=g.length,a1=f.length,a2=0,a3=0;a3<r;++a3){a4=d.$1(a2)
if(typeof a4!=="number")return a4.bA()
if(!(a3<a0))return A.a(g,a3)
a5=d.$1(a2+g[a3])
if(typeof a5!=="number")return a5.bA()
if(!(a3<a1))return A.a(f,a3)
a6=f[a3]
a7=i[a3]
if(!(a3<q))return A.a(h,a3)
a8=d.$1(a2+h[a3])
a9=d.$1(a2)
if(typeof a8!=="number")return a8.cz()
if(typeof a9!=="number")return A.hU(a9)
b0=a?!0:e.cb(0,a3)
B.a.j(b9,new A.ap(b2,a6,a7,a4+b,a5+b,a8-a9,b0))
a2+=h[a3]}r=j.a
q=j.w
if(r){r=j.b
r.toString
q=new A.aA(r,j.d,j.e,0,1,q,b3)
r=q}else{r=j.c
r.toString
q=new A.ad(r,j.f,j.r,q)
r=q}B.a.j(b8,r)},
iG(a,b){var s,r,q,p,o,n,m
if(b==null)return 0
s=b.b
r=a.getUint8(s)===1?32:20
q=s+4+r+16
if(q+36>b.c)return 0
p=a.getInt32(q,!1)
o=a.getInt32(q+4,!1)
n=a.getInt32(q+12,!1)
m=a.getInt32(q+16,!1)
if(p===65536&&o===0&&n===0&&m===65536)return 0
s=p===0
if(s&&o===65536&&n===-65536&&m===0)return 90
if(p===-65536&&o===0&&n===0&&m===-65536)return 180
if(s&&o===-65536&&n===65536&&m===0)return 270
return 0},
b1(a,b,c){return new A.br(A.kk(a,b,c),t.g6)},
kk(a,b,c){return function(){var s=a,r=b,q=c
var p=0,o=2,n=[],m,l,k,j,i,h,g,f
return function $async$b1(d,e,a0){if(e===1){n.push(a0)
p=o}for(;;)switch(p){case 0:m=r
case 3:if(!(l=m+8,l<=q)){p=5
break}k=s.getUint32(m,!1)
j=A.hE(s,m+4)
if(k===1){if(m+16>q){p=1
break}i=s.getUint32(l,!1)
h=s.getUint32(m+12,!1)
k=(B.b.ab(i,32)|h)>>>0
g=16}else{if(k===0)k=q-m
g=8}if(k<g||m+k>q){p=1
break}f=m+k
p=6
return d.b=new A.d6(j,m+g,f),1
case 6:case 4:m=f
p=3
break
case 5:case 1:return 0
case 2:return d.c=n.at(-1),3}}}},
J(a,b,c){var s,r,q
for(s=A.b1(a,b.b,b.c),r=s.$ti,s=new A.A(s.a(),r.h("A<1>")),r=r.c;s.n();){q=s.b
if(q==null)q=r.a(q)
if(q.a===c)return q}return null},
hE(a,b){var s,r=A.f([],t.t)
for(s=0;s<4;++s)r.push(a.getUint8(b+s))
return A.fn(r,0,null)},
hg(a,b,c,d){return new A.d8(!1,null,a,0,0,b,c,d)},
k0(a2,a3,a4){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b=null,a=A.b1(a2,a3.b+8,a3.c),a0=a.$ti,a1=new A.A(a.a(),a0.h("A<1>"))
if(a1.n()){a=a1.b
s=a==null?a0.c.a(a):a}else s=b
if(s==null)return b
r=s.a
if(a4){a=s.b
q=a2.getUint16(a+24,!1)
p=a2.getUint16(a+26,!1)
a=A.b1(a2,a+78,s.c)
a0=a.$ti
a=new A.A(a.a(),a0.h("A<1>"))
a0=a0.c
for(;;){if(!a.n()){o=b
break}n=a.b
if(n==null)n=a0.a(n)
m=n.a
if(m==="avcC"||m==="hvcC"||m==="av1C"){a=n.b
n=n.c
o=A.d0(J.fd(B.j.gI(a2),a2.byteOffset),a,n)
break}}switch(r){case"avc1":case"avc3":l=B.S
break
case"hev1":case"hvc1":l=B.T
break
case"av01":l=B.U
break
default:return b}return new A.d8(!0,l,b,q,p,0,0,o==null?b:new A.ah(l,b,o))}a=s.b
k=a2.getUint16(a+16,!1)
j=a2.getUint32(a+24,!1)>>>16
i=a+28
if(r==="mp4a"){a=A.b1(a2,i,s.c)
a0=a.$ti
a=new A.A(a.a(),a0.h("A<1>"))
a0=a0.c
for(;;){if(!a.n()){h=b
break}n=a.b
if(n==null)n=a0.a(n)
if(n.a==="esds"){h=A.js(a2,n)
break}}if(j!==0)a=j
else a=h==null?0:A.jt(h)
return A.hg(B.f,a,k,h==null?b:new A.ah(b,B.f,h))}if(r==="Opus"){a=A.b1(a2,i,s.c)
a0=a.$ti
a=new A.A(a.a(),a0.h("A<1>"))
a0=a0.c
for(;;){if(!a.n()){g=b
break}n=a.b
if(n==null)n=a0.a(n)
if(n.a==="dOps"){f=new Uint8Array(19)
B.d.P(f,0,8,new A.cE("OpusHead"))
f[8]=1
a=n.b
e=a2.getUint8(a+1)
f[9]=e===0?k:e
d=a2.getUint16(a+2,!1)
c=A.a2(f,0,b)
c.$flags&2&&A.z(c,10)
c.setUint16(10,d,!0)
c.setUint32(12,j===0?48e3:j,!0)
g=f
break}}a=j===0?48e3:j
return A.hg(B.h,a,k,g==null?b:new A.ah(b,B.h,g))}return b},
jt(a){var s,r,q,p={}
p.a=0
p=new A.eQ(p,a)
s=p.$1(5)
if((s===31?p.$1(6):s)<0)return 0
r=p.$1(4)
if(r<0)return 0
if(r===15){q=p.$1(24)
return q<0?0:q}return r<13?B.aO[r]:0},
js(a,b){var s,r,q,p,o,n,m=A.fz(a,b.b+4,b.c)
if(m==null||m.a!==3)return null
s=m.b+3
for(r=m.c;s<r;){q=A.fz(a,s,r)
if(q==null)break
if(q.a===4){p=q.b+13
for(o=q.c;p<o;){n=A.fz(a,p,o)
if(n==null)break
if(n.a===5){r=n.b
o=n.c
return A.d0(J.fd(B.j.gI(a),a.byteOffset),r,o)}p=n.d}}s=q.d}return null},
fz(a,b,c){var s,r,q,p,o,n,m=b+1
if(m>c)return null
s=a.getUint8(b)
for(r=0,q=0;q<4;++q,m=p){if(m>=c)return null
p=m+1
o=a.getUint8(m)
r=(r<<7|o&127)>>>0
if((o&128)===0){m=p
break}}n=m+r
if(n>c)return null
return new A.eg(s,m,n,n)},
k2(a,b){var s,r,q,p,o
if(b==null)return B.O
s=b.b+4
r=a.getUint32(s,!1)
q=a.getUint32(s+4,!1)
s+=8
if(r!==0)return A.aM(q,r,!1,t.S)
p=A.aM(q,0,!1,t.S)
for(o=0;o<q;++o)B.a.q(p,o,a.getUint32(s+o*4,!1))
return p},
k3(a,b,c){var s,r,q,p,o,n,m,l,k=A.aM(c,0,!1,t.S)
if(b==null)return k
s=b.b+4
r=a.getUint32(s,!1)
s+=4
q=0
p=0
for(;;){if(!(p<r&&q<c))break
o=a.getUint32(s,!1)
n=a.getUint32(s+4,!1)
s+=8
m=0
for(;;){if(!(m<o&&q<c))break
l=q+1
B.a.q(k,q,n);++m
q=l}++p}return k},
jZ(a,b,c){var s,r,q,p,o,n,m,l,k,j,i,h=A.aM(c,0,!1,t.S)
if(b==null)return h
s=b.b
r=a.getUint8(s)
q=s+4
p=a.getUint32(q,!1)
q+=4
s=r===1
o=0
n=0
for(;;){if(!(n<p&&o<c))break
m=a.getUint32(q,!1)
l=q+4
k=s?a.getInt32(l,!1):a.getUint32(l,!1)
q+=8
j=0
for(;;){if(!(j<m&&o<c))break
i=o+1
B.a.q(h,o,k);++j
o=i}++n}return h},
k_(a,b,c){var s,r,q,p,o,n,m,l,k,j,i,h,g,f
if(b==null||c<=0)return B.W
s=A.J(a,b,"elst")
if(s==null||s.b+8>s.c)return B.W
r=s.b
q=a.getUint8(r)===1
p=q?20:12
o=r+4
n=a.getUint32(o,!1)
o+=4
for(r=s.c,m=0,l=0,k=!1,j=0;j<n;++j,o=i){i=o+p
if(i>r)break
h=o+4
if(q){g=(B.b.ab(a.getUint32(o,!1),32)|a.getUint32(h,!1))>>>0
h=o+8
f=a.getInt32(h,!1)*4294967296+a.getUint32(h+4,!1)}else{g=a.getUint32(o,!1)
f=a.getInt32(h,!1)}if(f<0){if(!k)m+=g
continue}if(!k){l=f
k=!0}}return new A.db(B.b.t(m*1e6,c),l)},
k1(a,b,c){var s,r,q,p
if(b==null)return null
s=b.b+4
r=a.getUint32(s,!1)
s+=4
q=A.iA(t.S)
for(p=0;p<r;++p){q.j(0,a.getUint32(s,!1)-1)
s+=4}return q},
ka(a0,a1,a2){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d=A.jY(a0,a1),c=A.J(a0,a1,"stsc"),b=a2.length,a=A.aM(b,0,!1,t.S)
if(d.length===0||c==null)return a
s=c.b+4
r=a0.getUint32(s,!1)
s+=4
q=t.t
p=A.f([],q)
o=A.f([],q)
for(n=0;n<r;++n){B.a.j(p,a0.getUint32(s,!1))
B.a.j(o,a0.getUint32(s+4,!1))
s+=12}m=0
n=0
l=1
k=0
for(;;){q=d.length
if(!(k<q&&m<b))break
j=o.length
i=p.length
h=k+1
for(;;){if(n<i){if(!(n>=0))return A.a(p,n)
g=p[n]<=h}else g=!1
if(!g)break
if(!(n>=0&&n<j))return A.a(o,n)
l=o[n];++n}if(!(k<q))return A.a(d,k)
f=d[k]
e=0
for(;;){if(!(e<l&&m<b))break
B.a.q(a,m,f)
if(!(m>=0&&m<b))return A.a(a2,m)
f+=a2[m];++m;++e}k=h}return a},
jY(a,b){var s,r,q,p,o,n,m=A.J(a,b,"stco")
if(m!=null){s=m.b+4
r=a.getUint32(s,!1)
s+=4
q=A.f([],t.t)
for(p=0;p<r;++p)q.push(a.getUint32(s+p*4,!1))
return q}o=A.J(a,b,"co64")
if(o!=null){s=o.b+4
r=a.getUint32(s,!1)
s+=4
q=A.f([],t.t)
for(p=0;p<r;++p){n=s+p*8
q.push((B.b.ab(a.getUint32(n,!1),32)|a.getUint32(n+4,!1))>>>0)}return q}return B.O},
d6:function d6(a,b,c){this.a=a
this.b=b
this.c=c},
ap:function ap(a,b,c,d,e,f,g){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f
_.r=g},
dP:function dP(a,b,c){var _=this
_.a=a
_.b=b
_.c=c
_.d=0
_.e=!1},
dR:function dR(){},
dQ:function dQ(a){this.a=a},
dS:function dS(){},
d8:function d8(a,b,c,d,e,f,g,h){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f
_.r=g
_.w=h},
eQ:function eQ(a,b){this.a=a
this.b=b},
eg:function eg(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
db:function db(a,b){this.a=a
this.b=b},
hQ(a,b){var s
if(a.length<8)return!1
for(s=0;s<8;++s)if(a[s]!==b[s])return!1
return!0},
iK(b1){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c,b,a,a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,b0=A.a2(b1,0,null)
if(b0.byteLength<27||!A.hL(b0,0))throw A.b(B.ad)
s=A.f([],t.r)
r=new A.d9($.bz())
for(q=-1,p=0;o=p+27,o<=b0.byteLength;p=l){if(!A.hL(b0,p))throw A.b(B.aq)
n=b0.getUint8(p+26)
m=o+n
if(m>b0.byteLength)throw A.b(B.an)
for(l=m,k=0;k<n;++k,l=i){j=b0.getUint8(o+k)
i=l+j
if(i>b0.byteLength)throw A.b(B.as)
r.j(0,J.cw(B.j.gI(b0),b0.byteOffset+l,j))
if(j<255){B.a.j(s,r.cq())
r.N(0)}}h=b0.getUint32(p+6,!0)
g=b0.getUint32(p+10,!0)
if(!(h===4294967295&&g===4294967295))q=(B.b.ab(g,32)|h)>>>0}if(s.length===0||!A.hQ(B.a.gbl(s),B.M))throw A.b(B.ab)
f=B.a.gbl(s)
if(f.length>=19){e=f[9]
d=(f[12]|f[13]<<8|f[14]<<16|f[15]<<24)>>>0
if(d<=0)d=48e3}else{d=48e3
e=2}c=B.a.bD(s,s.length>1&&A.hQ(s[1],B.aN)?2:1)
b=A.kL(f)
o=c.length
a=t.S
a0=A.aM(o,0,!1,a)
a1=c.length
a2=A.aM(a1,0,!1,a)
for(a3=0,k=0;k<c.length;++k){a4=A.kM(c[k])
B.a.q(a2,k,a4>0?a4:960)
a5=a3-b
B.a.q(a0,k,a5>0?a5:0)
if(!(k<a1))return A.a(a2,k)
a3+=a2[k]}a6=(q>b?q:a3)-b
for(a=a6>0,k=0;a7=c.length,k<a7;k=a8){a8=k+1
if(a8<a7){if(!(a8<o))return A.a(a0,a8)
a9=a0[a8]}else a9=a?a6:0
if(!(k<o))return A.a(a0,k)
a4=a9-a0[k]
if(a4<0)a7=0
else{if(!(k<a1))return A.a(a2,k)
a7=a2[k]
a7=a4>a7?a7:a4}B.a.q(a2,k,a7)}o=A.f([new A.ad(B.h,d,e,new A.ah(null,B.h,f))],t.J)
return new A.dU(o,c,a0,a2,a6<0?0:a6)},
hL(a,b){var s
if(b+4>a.byteLength)return!1
for(s=0;s<4;++s)if(a.getUint8(b+s)!==B.aG[s])return!1
return!0},
dU:function dU(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=0
_.r=!1},
bu(a){var s
switch(a.a){case 0:s=1
break
case 1:s=2
break
case 2:s=3
break
case 3:s=4
break
default:s=null}return s},
iV(a){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c="wav",b=A.a2(a,0,null)
if(b.byteLength<12||!A.hD(b,0,"RIFF")||!A.hD(b,8,"WAVE"))throw A.b(B.ar)
for(s=-1,r=0,q=-1,p=0,o=12;n=o+8,n<=b.byteLength;o=j){m=A.k5(b,o)
l=b.getUint32(o+4,!0)
if(m==="fmt "){r=l
s=n}else if(m==="data"){k=b.byteLength
p=n+l>k?k-n:l
if(l===0){p=k-n
q=n
break}q=n}j=(n+l+1&4294967294)>>>0
if(j<=o)break}if(s<0||r<16)throw A.b(B.ap)
if(q<0)throw A.b(B.al)
i=b.getUint16(s,!0)
h=b.getUint16(s+2,!0)
g=b.getUint32(s+4,!0)
f=b.getUint16(s+14,!0)
if(i===65534){if(r<40||s+40>b.byteLength)throw A.b(B.ak)
e=b.getUint16(s+18,!0)
k=s+24
if(!A.jQ(b,k))throw A.b(B.ac)
i=b.getUint16(k,!0)}else e=f
k=i===1
if(!k&&i!==3)throw A.b(A.dB(c,"unsupported WAVE format tag "+i))
if(e===0)e=f
if(e!==f)throw A.b(A.dB(c,"valid bits "+e+" != container "+f))
if(k&&f===8)d=B.X
else if(k&&f===16)d=B.Y
else if(k&&f===24)d=B.Z
else{if(!(i===3&&f===32))throw A.b(A.dB(c,"unsupported PCM: fmt="+i+" bits="+f))
d=B.a_}A:{if(B.X===d||B.Y===d){k=B.w
break A}if(B.Z===d||B.a_===d){k=B.x
break A}k=null}if(h<1||h>8||g<1)throw A.b(A.dB(c,"bad ch="+h+" sr="+g))
return new A.e7(b,q,p,g,h,d,A.f([new A.ad(k,g,h,null)],t.J))},
jQ(a,b){var s,r
if(b+16>a.byteLength)return!1
for(s=b+2,r=0;r<14;++r)if(a.getUint8(s+r)!==B.aK[r])return!1
return!0},
hD(a,b,c){var s,r,q
if(b+4>a.byteLength)return!1
for(s=c.length,r=0;r<4;++r){q=a.getUint8(b+r)
if(!(r<s))return A.a(c,r)
if(q!==c.charCodeAt(r))return!1}return!0},
k5(a,b){var s,r=A.f([],t.t)
for(s=0;s<4;++s)r.push(a.getUint8(b+s))
return A.fn(r,0,null)},
aZ:function aZ(a,b){this.a=a
this.b=b},
e7:function e7(a,b,c,d,e,f,g){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f
_.r=g
_.w=0
_.x=!1},
du(a){return A.ks(a)},
ks(a){var s=0,r=A.G(t.H),q=1,p=[],o,n,m,l
var $async$du=A.H(function(b,c){if(b===1){p.push(c)
s=q}for(;;)switch(s){case 0:n={}
m=a.r
m.toString
t.eE.a(m)
n.a=null
a.ci(new A.f0(n,m))
s=2
return A.cp(a.c.a,$async$du)
case 2:q=4
n=n.a
n=n==null?null:n.u()
s=7
return A.cp(n instanceof A.j?n:A.fp(n,t.H),$async$du)
case 7:q=1
s=6
break
case 4:q=3
l=p.pop()
s=6
break
case 3:s=1
break
case 6:return A.E(null,r)
case 1:return A.D(p.at(-1),r)}})
return A.F($async$du,r)},
kJ(){A.kN()
A.kP(A.kv())
return null},
f0:function f0(a,b){this.a=a
this.b=b},
W:function W(a,b){this.a=a
this.b=b},
Z:function Z(a,b){this.a=a
this.b=b},
I:function I(a,b){this.a=a
this.b=b},
ak:function ak(){},
aA:function aA(a,b,c,d,e,f,g){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f
_.r=g},
ad:function ad(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
kN(){var s=$.fO()
s.bq(3329,A.ku())
s.bq(3330,A.kt())},
iU(a){var s,r,q,p,o,n,m,l,k,j,i,h,g,f,e,d,c=null,b="demux protocol: truncated message (wanted 4 bytes at "
t.p.a(a)
s=A.a2(a,0,c)
r=new A.dg(a,s)
q=r.O()===1?r.X():c
p=r.O()
o=r.bw()
n=A.f([],t.J)
for(m=t.q,l=t.G,k=0;k<o;++k){j=r.c
i=j+1
h=a.byteLength
if(i>h)A.n(A.a3("demux protocol: truncated message (wanted 1 bytes at "+j+" of "+h+")",c,c))
r.c=i
switch(s.getUint8(j)){case 0:j=A.cI(B.P,r.al(),l)
i=r.c
h=a.byteLength
if(i+4>h)A.n(A.a3(b+i+" of "+h+")",c,c))
g=s.getUint32(i,!0)
i=r.c+=4
h=a.byteLength
if(i+4>h)A.n(A.a3(b+i+" of "+h+")",c,c))
f=s.getUint32(i,!0)
i=r.c+=4
h=a.byteLength
if(i+4>h)A.n(A.a3(b+i+" of "+h+")",c,c))
e=s.getUint32(i,!0)
i=r.c+=4
h=a.byteLength
if(i+4>h)A.n(A.a3(b+i+" of "+h+")",c,c))
d=s.getUint32(i,!0)
r.c+=4
i=r.X()
B.a.j(n,new A.aA(j,g,f,e,d,r.bj(),i))
break
case 1:j=A.cI(B.Q,r.al(),m)
i=r.c
h=a.byteLength
if(i+4>h)A.n(A.a3(b+i+" of "+h+")",c,c))
g=s.getUint32(i,!0)
i=r.c+=4
h=a.byteLength
if(i+4>h)A.n(A.a3(b+i+" of "+h+")",c,c))
f=s.getUint32(i,!0)
r.c+=4
B.a.j(n,new A.ad(j,g,f,r.bj()))
break
default:throw A.b(B.az)}}return new A.aR(n,q,p===1)},
iL(a){var s,r,q,p,o,n
t.p.a(a)
s=new A.dg(a,A.a2(a,0,null))
r=s.X()
q=s.X()
p=s.X()
o=s.O()
n=s.af()
return new A.aP(new A.ai(s.bf(),r,q,p,o===1,n))},
hw(){var s=A.f([],t.r)
return new A.eO(new A.d7(s),new Uint8Array(8))},
aR:function aR(a,b,c){this.a=a
this.b=b
this.c=c},
aP:function aP(a){this.a=a},
eO:function eO(a,b){this.a=a
this.b=b
this.c=$},
dg:function dg(a,b){this.a=a
this.b=b
this.c=0},
dB(a,b){return new A.w(a,b)},
dN:function dN(){},
w:function w(a,b){this.b=a
this.a=b},
aG:function aG(a,b){this.b=a
this.a=b},
ai:function ai(a,b,c,d,e,f){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e
_.f=f},
ah:function ah(a,b,c){this.a=a
this.b=b
this.c=c},
kP(a){var s,r,q={}
q.a=null
s=A.b_(v.G.self)
q=new A.fb(q,a)
if(typeof q=="function")A.n(A.cz("Attempting to rewrap a JS function.",null))
r=function(b,c){return function(d){return b(c,d,arguments.length)}}(A.jv,q)
r[$.fN()]=q
s.onmessage=r},
jx(a){var s,r,q,p,o,n,m,l,k,j,i,h=null
if(a!=null){q=A.ix(a,"Object")
q=!q}else q=!0
if(q)return h
A.b_(a)
s=t.dE.a(a.h)
if(s==null)return h
r=null
try{q=s
p=q.byteLength
if(p<12)A.n(A.a3("spawn envelope: need at least 12 bytes, got "+p,h,h))
o=A.a2(q,0,12)
n=o.getUint8(0)
if(n!==1)A.n(A.a3("spawn envelope: unsupported version "+n+" (expected 1)",h,h))
m=o.getUint8(1)
l=A.iW(m)
if(l==null)A.n(A.a3("spawn envelope: unknown kind "+m,h,h))
r=new A.d3(n,l,o.getUint16(2,!0),o.getUint32(4,!0),o.getUint32(8,!0))}catch(k){if(A.R(k) instanceof A.bI)return h
else throw k}j=a.p
if(j==null)i=h
else i=r.c!==0||r.b===B.t||r.b===B.u||r.b===B.k?t.Y.a(j):A.fw(j)
return new A.S(r.b,r.c,r.d,i)},
kh(a,b){var s,r,q=t.c.a(new v.G.Array()),p=new A.eZ(A.f([],t.f),q)
for(s=b.length,r=0;r<b.length;b.length===s||(0,A.b5)(b),++r)p.$1(b[r])
return q},
fC(a,b){var s,r,q,p,o
if(a==null)return null
if(a instanceof A.bU){s={}
r=a.a
s.$spawn$platform=r
if(r!=null&&A.hB(r)!=="SharedArrayBuffer")B.a.j(b,r)
return s}if(A.dn(a))return a
if(A.cq(a))return a
if(typeof a=="number")return a
if(typeof a=="string")return a
if(t.x.b(a))return t.u.a(a)
if(t.p.b(a))return a
if(t.U.b(a))return a
if(t.go.b(a))return a
if(t.dQ.b(a))return a
if(t.h7.b(a))return a
if(t.an.b(a))return a
if(t.bv.b(a))return a
if(t.h4.b(a))return a
if(t.gN.b(a))return a
if(t.W.b(a))return a
if(t.j.b(a)){q=t.c.a(new v.G.Array())
for(p=0;o=J.ct(a),p<o.gk(a);++p)q[p]=A.fC(o.m(a,p),b)
return q}if(a instanceof A.Q){s={}
a.W(0,new A.eY(s,b))
return s}throw A.b(A.au(a,"message","spawn cannot carry this value"))},
fw(a){var s,r,q,p
if(a==null)return null
if(typeof a==="boolean")return A.hy(a)
if(typeof a==="string")return A.aq(a)
if(typeof a==="number"){A.dm(a)
if(isFinite(a))s=a===(a<0?Math.ceil(a):Math.floor(a))
else s=!1
if(s)return B.I.cr(a)
return a}if(!(typeof a==="object"))return null
switch(A.hB(a)){case"ArrayBuffer":return t.u.a(a)
case"Uint8Array":return t.Y.a(a)
case"Int8Array":return t.cv.a(a)
case"Uint8ClampedArray":return t.gi.a(a)
case"Int16Array":return t.at.a(a)
case"Uint16Array":return t.d.a(a)
case"Int32Array":return t.ha.a(a)
case"Uint32Array":return t.dk.a(a)
case"Float32Array":return t.E.a(a)
case"Float64Array":return t.c2.a(a)
case"DataView":return t.A.a(a)
case"Array":t.c.a(a)
r=A.aa(A.dm(a.length))
s=[]
for(q=0;q<r;++q)s.push(A.fw(a[q]))
return s
default:A.b_(a)
if("$spawn$platform" in a)return new A.bU(a.$spawn$platform)
p=t.c.a(v.G.Object.keys(a))
r=A.aa(A.dm(p.length))
s=A.fZ(t.N,t.X)
for(q=0;q<r;++q)s.q(0,A.aq(p[q]),A.fw(a[A.aq(p[q])]))
return s}},
hB(a){var s,r=A.fu(A.b_(a).constructor)
if(r==null)s=null
else{s=A.eP(r.name)
if(s==null)s=null}return s},
fb:function fb(a,b){this.a=a
this.b=b},
fa:function fa(){},
dl:function dl(a,b){this.a=a
this.b=b},
eZ:function eZ(a,b){this.a=a
this.b=b},
eY:function eY(a,b){this.a=a
this.b=b},
cV:function cV(a,b){this.a=a
this.b=b},
cW:function cW(a,b){this.a=a
this.b=b},
dW:function dW(){},
dw(a,b,c,d){return A.kO(a,b,c,d)},
kO(a,b,c,a0){var s=0,r=A.G(t.H),q=1,p=[],o=[],n,m,l,k,j,i,h,g,f,e,d
var $async$dw=A.H(function(a1,a2){if(a1===1){p.push(a2)
s=q}for(;;)switch(s){case 0:f=t.X
e=new A.cn(a,A.hb(f),new A.bl(new A.j($.i,t.D),t.h),A.f([],t.b4),c)
a.M(new A.S(B.t,0,0,B.e.J(B.a9.ce(A.h_(["v",1,"caps",a0.bu()],t.N,f),null))))
f=a.a
n=new A.bn(f,A.B(f).h("bn<1>")).ck(e.gbV(),e.gbX())
q=3
f=b.$1(e)
s=6
return A.cp(f instanceof A.j?f:A.fp(f,t.H),$async$dw)
case 6:o.push(5)
s=4
break
case 3:q=2
d=p.pop()
m=A.R(d)
l=A.Y(d)
f=A.ab(m)
j=t.l.a(l)
i=e.a
h=J.as(f)
g=A.L(h.gl(f).a,null)
f=h.i(f)
j=j.i(0)
i.M(new A.S(B.k,0,0,B.e.J(g+"\n"+A.fM(f,"\n"," ")+"\n"+j)))
o.push(5)
s=4
break
case 2:o=[1]
case 4:q=1
e.av()
f=n
if(((f.e&=4294967279)&8)===0)f.aS()
f=f.f
s=7
return A.cp(f==null?$.fc():f,$async$dw)
case 7:a.M(B.aA)
s=o.pop()
break
case 5:return A.E(null,r)
case 1:return A.D(p.at(-1),r)}})
return A.F($async$dw,r)},
cn:function cn(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=null
_.f=!1
_.r=e},
eL:function eL(a,b){this.a=a
this.b=b},
eM:function eM(a,b){this.a=a
this.b=b},
eN:function eN(a,b){this.a=a
this.b=b},
S:function S(a,b,c,d){var _=this
_.a=a
_.b=b
_.c=c
_.d=d},
kx(a){var s
if(t.bG.b(a)){s=a.gbv()
if(s<1||s>65535)throw A.b(A.au(s,"typeId",A.fH(a).i(0)+".typeId must be in 1..65535 (0 is reserved)"))
return new A.bq(s,a.bi())}A.fv(a,A.f([],t.f),"message")
return new A.bq(0,a)},
fF(a,b){var s
if(a===0)return b
if(!t.p.b(b))throw A.b(A.af("spawn: frame declares typeId "+a+" but carries "+J.bA(b).i(0)+" instead of bytes"))
s=$.fO().a.m(0,a)
if(s==null)A.n(A.af("spawn: no WireMessage decoder registered for typeId "+a+". Both ends must call the same WireRegistry.instance.register(...)."))
return s.$1(b)},
fv(a,b,c){var s,r,q,p
if(a==null||A.dn(a)||typeof a=="number"||typeof a=="string"||t.ak.b(a)||t.x.b(a)||a instanceof A.bU)return
s=t.j.b(a)
if(s||a instanceof A.Q){for(r=b.length,q=0;q<r;++q)if(b[q]===a)throw A.b(A.au(a,c,"spawn cannot carry a cyclic structure"))
B.a.j(b,a)
if(s)for(s=c+"[",p=0;r=J.ct(a),p<r.gk(a);++p)A.fv(r.m(a,p),b,s+p+"]")
else if(a instanceof A.Q)a.W(0,new A.eT(c,b))
if(0>=b.length)return A.a(b,-1)
b.pop()
return}throw A.b(A.au(a,c,"spawn cannot carry "+J.bA(a).i(0)+". Wrap a platform object (VideoFrame, AudioData, ImageBitmap, ...) in a PlatformValue. Portable values are null, bool, int, double, String, TypedData, ByteBuffer, and List/Map<String, ...> of those. Implement WireMessage for anything else."))},
eT:function eT(a,b){this.a=a
this.b=b},
bU:function bU(a){this.a=a},
iW(a){var s,r
for(s=0;s<6;++s){r=B.aF[s]
if(r.c===a)return r}return null},
ag:function ag(a,b,c){this.c=a
this.a=b
this.b=c},
d3:function d3(a,b,c,d,e){var _=this
_.a=a
_.b=b
_.c=c
_.d=d
_.e=e},
e8:function e8(a){this.a=a},
a2(a,b,c){var s=a.BYTES_PER_ELEMENT
c=A.bY(b,c,B.b.t(a.byteLength,s))
return J.ie(B.d.gI(a),a.byteOffset+b*s,(c-b)*s)},
d0(a,b,c){var s=a.BYTES_PER_ELEMENT
c=A.bY(b,c,B.b.t(a.byteLength,s))
return J.cw(B.d.gI(a),a.byteOffset+b*s,(c-b)*s)},
ix(a,b){var s,r,q,p,o
if(b.length===0)return!1
s=b.split(".")
r=v.G
for(q=s.length,p=0;p<q;++p,r=o){o=r[s[p]]
A.fu(o)
if(o==null)return!1}return a instanceof t.g.a(r)},
jv(a,b,c){t.Z.a(a)
if(A.aa(c)>=1)return a.$1(b)
return a.$0()},
ir(a,b){var s,r,q,p,o,n,m
switch(b==null?A.is(a):b){case B.q:return A.iV(a)
case B.p:return A.iK(a)
case B.o:s=A.a2(a,0,null)
r=A.ff(a)
q=A.eV(s,r)
if(q==null)A.n(B.am)
p=q.b
if(!(p<16))return A.a(B.N,p)
o=B.N[p]
if(o!==0){n=q.c
n=(n===7?8:n)<1}else n=!0
if(n)A.n(B.af)
n=q.c
m=new Uint8Array(2)
m[0]=p>>>1&7|16
m[1]=(p&1)<<7|(n&15)<<3
p=n===7?8:n
return new A.dy(A.f([new A.ad(B.f,o,p,new A.ah(null,B.f,m))],t.J),a,s,o,r,q.a)
case B.l:return A.iE(a)
case B.n:case B.H:return A.iH(a)
default:return null}},
is(a){var s,r,q,p,o,n=a.length
if(n>=12&&a[0]===82&&a[1]===73&&a[2]===70&&a[3]===70&&a[8]===87&&a[9]===65&&a[10]===86&&a[11]===69)return B.q
if(n>=4&&a[0]===79&&a[1]===103&&a[2]===103&&a[3]===83)return B.p
if(n>=8&&a[4]===102&&a[5]===116&&a[6]===121&&a[7]===112)return B.n
s=A.cu(a,0)
r=0
for(;;){if(!(s>0&&r+s<=n))break
r+=s
s=A.cu(a,r)}q=r>0
if(q)for(;;){if(!(r<n&&a[r]===0))break;++r}if(r+2<=n){if(!(r>=0&&r<n))return A.a(a,r)
p=a[r]
o=r+1
if(!(o<n))return A.a(a,o)
o=a[o]
if(p===255&&(o&246)===240)return B.o
if(A.fJ(p,o))return B.l}if(q)return B.l
return null},
kL(a){var s
if(a.length<12)return 0
for(s=0;s<8;++s)if(a[s]!==B.M[s])return 0
return(a[10]|a[11]<<8)>>>0},
kM(a){var s,r,q,p,o=a.length
if(o===0)return 0
if(0>=o)return A.a(a,0)
s=a[0]
r=B.aI[s>>>3&31]
switch(s&3){case 0:q=1
break
case 1:case 2:q=2
break
default:if(o<2)return 0
q=a[1]&63}if(q<1||q>48)return 0
p=r*q
return p>5760?0:p}},B={}
var w=[A,J,B]
var $={}
A.fj.prototype={}
J.cL.prototype={
K(a,b){return a===b},
gp(a){return A.bV(a)},
i(a){return"Instance of '"+A.cT(a)+"'"},
gl(a){return A.ac(A.fx(this))}}
J.cN.prototype={
i(a){return String(a)},
gp(a){return a?519018:218159},
gl(a){return A.ac(t.y)},
$il:1,
$ib2:1}
J.bK.prototype={
K(a,b){return null==b},
i(a){return"null"},
gp(a){return 0},
gl(a){return A.ac(t.P)},
$il:1,
$iu:1}
J.bM.prototype={$ir:1}
J.aw.prototype={
gp(a){return 0},
gl(a){return B.aW},
i(a){return String(a)}}
J.cS.prototype={}
J.c2.prototype={}
J.aj.prototype={
i(a){var s=a[$.fN()]
if(s==null)return this.bE(a)
return"JavaScript function for "+J.cy(s)},
$iaI:1}
J.b8.prototype={
gp(a){return 0},
i(a){return String(a)}}
J.b9.prototype={
gp(a){return 0},
i(a){return String(a)}}
J.o.prototype={
j(a,b){A.a9(a).c.a(b)
a.$flags&1&&A.z(a,29)
a.push(b)},
N(a){a.$flags&1&&A.z(a,"clear","clear")
a.length=0},
bt(a,b){return A.cZ(a,0,A.ds(b,"count",t.S),A.a9(a).c)},
aj(a,b){return A.cZ(a,b,null,A.a9(a).c)},
V(a,b){if(!(b>=0&&b<a.length))return A.a(a,b)
return a[b]},
bD(a,b){var s=a.length
if(b>s)throw A.b(A.a4(b,0,s,"start",null))
if(b===s)return A.f([],A.a9(a))
return A.f(a.slice(b,s),A.a9(a))},
gbl(a){if(a.length>0)return a[0]
throw A.b(A.fV())},
c8(a,b){var s,r
A.a9(a).h("b2(1)").a(b)
s=a.length
for(r=0;r<s;++r){if(b.$1(a[r]))return!0
if(a.length!==s)throw A.b(A.bD(a))}return!1},
bC(a,b){var s,r,q,p,o,n=A.a9(a)
n.h("c(1,1)?").a(b)
a.$flags&2&&A.z(a,"sort")
s=a.length
if(s<2)return
if(s===2){r=a[0]
q=a[1]
n=b.$2(r,q)
if(typeof n!=="number")return n.cw()
if(n>0){a[0]=q
a[1]=r}return}p=0
if(n.c.b(null))for(o=0;o<a.length;++o)if(a[o]===void 0){a[o]=null;++p}a.sort(A.dt(b,2))
if(p>0)this.c0(a,p)},
c0(a,b){var s,r=a.length
for(;s=r-1,r>0;r=s)if(a[s]===null){a[s]=void 0;--b
if(b===0)break}},
gbn(a){return a.length!==0},
i(a){return A.fi(a,"[","]")},
gE(a){return new J.bB(a,a.length,A.a9(a).h("bB<1>"))},
gp(a){return A.bV(a)},
gk(a){return a.length},
m(a,b){if(!(b>=0&&b<a.length))throw A.b(A.f1(a,b))
return a[b]},
q(a,b,c){A.a9(a).c.a(c)
a.$flags&2&&A.z(a)
if(!(b>=0&&b<a.length))throw A.b(A.f1(a,b))
a[b]=c},
gl(a){return A.ac(A.a9(a))},
$ie:1,
$ik:1}
J.cM.prototype={
cs(a){var s,r,q
if(!Array.isArray(a))return null
s=a.$flags|0
if((s&4)!==0)r="const, "
else if((s&2)!==0)r="unmodifiable, "
else r=(s&1)!==0?"fixed, ":""
q="Instance of '"+A.cT(a)+"'"
if(r==="")return q
return q+" ("+r+"length: "+a.length+")"}}
J.dI.prototype={}
J.bB.prototype={
gv(){var s=this.d
return s==null?this.$ti.c.a(s):s},
n(){var s,r=this,q=r.a,p=q.length
if(r.b!==p){q=A.b5(q)
throw A.b(q)}s=r.c
if(s>=p){r.d=null
return!1}r.d=q[s]
r.c=s+1
return!0},
$iae:1}
J.bL.prototype={
aC(a,b){var s
A.hz(b)
if(a<b)return-1
else if(a>b)return 1
else if(a===b){if(a===0){s=this.gaF(b)
if(this.gaF(a)===s)return 0
if(this.gaF(a))return-1
return 1}return 0}else if(isNaN(a)){if(isNaN(b))return 0
return 1}else return-1},
gaF(a){return a===0?1/a<0:a<0},
cr(a){var s
if(a>=-2147483648&&a<=2147483647)return a|0
if(isFinite(a)){s=a<0?Math.ceil(a):Math.floor(a)
return s+0}throw A.b(A.e4(""+a+".toInt()"))},
c9(a,b,c){if(B.b.aC(b,c)>0)throw A.b(A.bx(b))
if(this.aC(a,b)<0)return b
if(this.aC(a,c)>0)return c
return a},
i(a){if(a===0&&1/a<0)return"-0.0"
else return""+a},
gp(a){var s,r,q,p,o=a|0
if(a===o)return o&536870911
s=Math.abs(a)
r=Math.log(s)/0.6931471805599453|0
q=Math.pow(2,r)
p=s<1?s/q:q/s
return((p*9007199254740992|0)+(p*3542243181176521|0))*599197+r*1259&536870911},
aL(a,b){var s=a%b
if(s===0)return 0
if(s>0)return s
return s+b},
t(a,b){if((a|0)===a)if(b>=1||b<-1)return a/b|0
return this.b9(a,b)},
F(a,b){return(a|0)===a?a/b|0:this.b9(a,b)},
b9(a,b){var s=a/b
if(s>=-2147483648&&s<=2147483647)return s|0
if(s>0){if(s!==1/0)return Math.floor(s)}else if(s>-1/0)return Math.ceil(s)
throw A.b(A.e4("Result of truncating division is "+A.p(s)+": "+A.p(a)+" ~/ "+b))},
ab(a,b){return b>31?0:a<<b>>>0},
H(a,b){var s
if(a>0)s=this.b7(a,b)
else{s=b>31?31:b
s=a>>s>>>0}return s},
c4(a,b){if(0>b)throw A.b(A.bx(b))
return this.b7(a,b)},
b7(a,b){return b>31?0:a>>>b},
gl(a){return A.ac(t.o)},
$im:1,
$ib4:1}
J.bJ.prototype={
gl(a){return A.ac(t.S)},
$il:1,
$ic:1}
J.cO.prototype={
gl(a){return A.ac(t.i)},
$il:1}
J.b7.prototype={
a3(a,b,c){return a.substring(b,A.bY(b,c,a.length))},
i(a){return a},
gp(a){var s,r,q
for(s=a.length,r=0,q=0;q<s;++q){r=r+a.charCodeAt(q)&536870911
r=r+((r&524287)<<10)&536870911
r^=r>>6}r=r+((r&67108863)<<3)&536870911
r^=r>>11
return r+((r&16383)<<15)&536870911},
gl(a){return A.ac(t.N)},
gk(a){return a.length},
$il:1,
$ih4:1,
$ia7:1}
A.d9.prototype={
j(a,b){var s,r,q=this
t.L.a(b)
s=b.length
if(s===0)return
r=q.a+s
if(q.b.length<r)q.b1(r)
B.d.P(q.b,q.a,r,b)
q.a=r},
D(a){var s=this,r=s.b,q=s.a
if(r.length===q)s.b1(q)
r=s.b
q=s.a
r.$flags&2&&A.z(r)
if(!(q<r.length))return A.a(r,q)
r[q]=a
s.a=q+1},
b1(a){var s,r,q,p=a*2
if(p<1024)p=1024
else{s=p-1
s|=B.b.H(s,1)
s|=s>>>2
s|=s>>>4
s|=s>>>8
p=((s|s>>>16)>>>0)+1}r=new Uint8Array(p)
q=this.b
B.d.P(r,0,q.length,q)
this.b=r},
aJ(){var s,r=this
if(r.a===0)return $.bz()
s=J.cw(B.d.gI(r.b),r.b.byteOffset,r.a)
r.a=0
r.b=$.bz()
return s},
cq(){var s=this
if(s.a===0)return $.bz()
return new Uint8Array(A.K(J.cw(B.d.gI(s.b),s.b.byteOffset,s.a)))},
gk(a){return this.a},
N(a){this.a=0
this.b=$.bz()},
$ifg:1}
A.d7.prototype={
j(a,b){t.L.a(b)
B.a.j(this.b,b)
this.a=this.a+b.length},
D(a){var s=new Uint8Array(1)
s[0]=a
B.a.j(this.b,s);++this.a},
aJ(){var s,r,q,p,o,n,m,l=this,k=l.a
if(k===0)return $.bz()
s=l.b
r=s.length
if(r===1){if(0>=r)return A.a(s,0)
q=s[0]
l.a=0
B.a.N(s)
return q}q=new Uint8Array(k)
for(p=0,o=0;o<s.length;s.length===r||(0,A.b5)(s),++o,p=m){n=s[o]
m=p+n.length
B.d.P(q,p,m,n)}l.a=0
B.a.N(s)
return q},
gk(a){return this.a},
$ifg:1}
A.ba.prototype={
i(a){return"LateInitializationError: "+this.a}}
A.cE.prototype={
gk(a){return this.a.length},
m(a,b){var s=this.a
if(!(b>=0&&b<s.length))return A.a(s,b)
return s.charCodeAt(b)}}
A.f9.prototype={
$0(){var s=new A.j($.i,t.D)
s.a5(null)
return s},
$S:10}
A.dV.prototype={}
A.bE.prototype={}
A.aK.prototype={
gE(a){var s=this
return new A.aL(s,s.gk(s),A.B(s).h("aL<aK.E>"))},
gZ(a){return this.gk(this)===0}}
A.c1.prototype={
gbQ(){var s=J.cx(this.a),r=this.c
if(r==null||r>s)return s
return r},
gc5(){var s=J.cx(this.a),r=this.b
if(r>s)return s
return r},
gk(a){var s,r=J.cx(this.a),q=this.b
if(q>=r)return 0
s=this.c
if(s==null||s>=r)return r-q
return s-q},
V(a,b){var s=this,r=s.gc5()+b
if(b<0||r>=s.gbQ())throw A.b(A.fh(b,s.gk(0),s,"index"))
return J.ig(s.a,r)},
aj(a,b){var s,r,q=this
A.bX(b,"count")
s=q.b+b
r=q.c
if(r!=null&&s>=r)return new A.bF(q.$ti.h("bF<1>"))
return A.cZ(q.a,s,r,q.$ti.c)}}
A.aL.prototype={
gv(){var s=this.d
return s==null?this.$ti.c.a(s):s},
n(){var s,r=this,q=r.a,p=J.ct(q),o=p.gk(q)
if(r.b!==o)throw A.b(A.bD(q))
s=r.c
if(s>=o){r.d=null
return!1}r.d=p.V(q,s);++r.c
return!0},
$iae:1}
A.bF.prototype={
gE(a){return B.a2},
gk(a){return 0}}
A.bG.prototype={
n(){return!1},
gv(){throw A.b(A.fV())},
$iae:1}
A.N.prototype={}
A.aS.prototype={
q(a,b,c){A.B(this).h("aS.E").a(c)
throw A.b(A.e4("Cannot modify an unmodifiable list"))}}
A.bk.prototype={}
A.bq.prototype={$r:"+(1,2)",$s:1}
A.bZ.prototype={}
A.e_.prototype={
G(a){var s,r,q=this,p=new RegExp(q.a).exec(a)
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
A.bT.prototype={
i(a){return"Null check operator used on a null value"}}
A.cP.prototype={
i(a){var s,r=this,q="NoSuchMethodError: method not found: '",p=r.b
if(p==null)return"NoSuchMethodError: "+r.a
s=r.c
if(s==null)return q+p+"' ("+r.a+")"
return q+p+"' on '"+s+"' ("+r.a+")"}}
A.d2.prototype={
i(a){var s=this.a
return s.length===0?"Error":"Error: "+s}}
A.dT.prototype={
i(a){return"Throw of null ('"+(this.a===null?"null":"undefined")+"' from JavaScript)"}}
A.bH.prototype={}
A.ce.prototype={
i(a){var s,r=this.b
if(r!=null)return r
r=this.a
s=r!==null&&typeof r==="object"?r.stack:null
return this.b=s==null?"":s},
$ia6:1}
A.av.prototype={
i(a){var s=this.constructor,r=s==null?null:s.name
return"Closure '"+A.hZ(r==null?"unknown":r)+"'"},
gl(a){var s=A.fE(this)
return A.ac(s==null?A.at(this):s)},
$iaI:1,
gcv(){return this},
$C:"$1",
$R:1,
$D:null}
A.cC.prototype={$C:"$0",$R:0}
A.cD.prototype={$C:"$2",$R:2}
A.d_.prototype={}
A.cX.prototype={
i(a){var s=this.$static_name
if(s==null)return"Closure of unknown static method"
return"Closure '"+A.hZ(s)+"'"}}
A.b6.prototype={
K(a,b){if(b==null)return!1
if(this===b)return!0
if(!(b instanceof A.b6))return!1
return this.$_target===b.$_target&&this.a===b.a},
gp(a){return(A.hV(this.a)^A.bV(this.$_target))>>>0},
i(a){return"Closure '"+this.$_name+"' of "+("Instance of '"+A.cT(this.a)+"'")}}
A.cU.prototype={
i(a){return"RuntimeError: "+this.a}}
A.aJ.prototype={
gk(a){return this.a},
gZ(a){return this.a===0},
gaG(){return new A.bP(this,this.$ti.h("bP<1>"))},
m(a,b){var s,r,q,p,o=null
if(typeof b=="string"){s=this.b
if(s==null)return o
r=s[b]
q=r==null?o:r.b
return q}else if(typeof b=="number"&&(b&0x3fffffff)===b){p=this.c
if(p==null)return o
r=p[b]
q=r==null?o:r.b
return q}else return this.cj(b)},
cj(a){var s,r,q=this.d
if(q==null)return null
s=q[J.P(a)&1073741823]
r=this.bm(s,a)
if(r<0)return null
return s[r].b},
q(a,b,c){var s,r,q,p,o,n,m=this,l=m.$ti
l.c.a(b)
l.y[1].a(c)
if(typeof b=="string"){s=m.b
m.aN(s==null?m.b=m.ar():s,b,c)}else if(typeof b=="number"&&(b&0x3fffffff)===b){r=m.c
m.aN(r==null?m.c=m.ar():r,b,c)}else{q=m.d
if(q==null)q=m.d=m.ar()
p=J.P(b)&1073741823
o=q[p]
if(o==null)q[p]=[m.am(b,c)]
else{n=m.bm(o,b)
if(n>=0)o[n].b=c
else o.push(m.am(b,c))}}},
W(a,b){var s,r,q=this
q.$ti.h("~(1,2)").a(b)
s=q.e
r=q.r
while(s!=null){b.$2(s.a,s.b)
if(r!==q.r)throw A.b(A.bD(q))
s=s.c}},
aN(a,b,c){var s,r=this.$ti
r.c.a(b)
r.y[1].a(c)
s=a[b]
if(s==null)a[b]=this.am(b,c)
else s.b=c},
am(a,b){var s=this,r=s.$ti,q=new A.dK(r.c.a(a),r.y[1].a(b))
if(s.e==null)s.e=s.f=q
else s.f=s.f.c=q;++s.a
s.r=s.r+1&1073741823
return q},
bm(a,b){var s,r
if(a==null)return-1
s=a.length
for(r=0;r<s;++r)if(J.cv(a[r].a,b))return r
return-1},
i(a){return A.h0(this)},
ar(){var s=Object.create(null)
s["<non-identifier-key>"]=s
delete s["<non-identifier-key>"]
return s},
$ifY:1}
A.dK.prototype={}
A.bP.prototype={
gk(a){return this.a.a},
gZ(a){return this.a.a===0},
gE(a){var s=this.a
return new A.bO(s,s.r,s.e,this.$ti.h("bO<1>"))}}
A.bO.prototype={
gv(){return this.d},
n(){var s,r=this,q=r.a
if(r.b!==q.r)throw A.b(A.bD(q))
s=r.c
if(s==null){r.d=null
return!1}else{r.d=s.a
r.c=s.c
return!0}},
$iae:1}
A.f4.prototype={
$1(a){return this.a(a)},
$S:3}
A.f5.prototype={
$2(a,b){return this.a(a,b)},
$S:11}
A.f6.prototype={
$1(a){return this.a(A.aq(a))},
$S:12}
A.aY.prototype={
gl(a){return A.ac(this.b0())},
b0(){return A.kz(this.$r,this.b_())},
i(a){return this.bb(!1)},
bb(a){var s,r,q,p,o,n=this.bS(),m=this.b_(),l=(a?"Record ":"")+"("
for(s=n.length,r="",q=0;q<s;++q,r=", "){l+=r
p=n[q]
if(typeof p=="string")l=l+p+": "
if(!(q<m.length))return A.a(m,q)
o=m[q]
l=a?l+A.h7(o):l+A.p(o)}l+=")"
return l.charCodeAt(0)==0?l:l},
bS(){var s,r=this.$s
while($.ey.length<=r)B.a.j($.ey,null)
s=$.ey[r]
if(s==null){s=this.bM()
B.a.q($.ey,r,s)}return s},
bM(){var s,r,q,p=this.$r,o=p.indexOf("("),n=p.substring(1,o),m=p.substring(o),l=m==="()"?0:m.replace(/[^,]/g,"").length+1,k=A.f(new Array(l),t.f)
for(s=0;s<l;++s)k[s]=s
if(n!==""){r=n.split(",")
s=r.length
for(q=l;s>0;){--q;--s
B.a.q(k,q,r[s])}}k=A.iB(k,!1,t.K)
k.$flags=3
return k}}
A.bp.prototype={
b_(){return[this.a,this.b]},
K(a,b){if(b==null)return!1
return b instanceof A.bp&&this.$s===b.$s&&J.cv(this.a,b.a)&&J.cv(this.b,b.b)},
gp(a){return A.h3(this.$s,this.a,this.b,B.i,B.i)}}
A.ef.prototype={}
A.ax.prototype={
gl(a){return B.aP},
ad(a,b,c){A.eU(a,b,c)
return c==null?new Uint8Array(a,b):new Uint8Array(a,b,c)},
bd(a,b){return this.ad(a,b,null)},
bc(a,b,c){var s
A.eU(a,b,c)
s=new DataView(a,b,c)
return s},
$il:1,
$iax:1,
$ibC:1}
A.bb.prototype={$ibb:1}
A.bS.prototype={
gI(a){if(((a.$flags|0)&2)!==0)return new A.dk(a.buffer)
else return a.buffer},
bU(a,b,c,d){var s=A.a4(b,0,c,d,null)
throw A.b(s)},
aU(a,b,c,d){if(b>>>0!==b||b>c)this.bU(a,b,c,d)},
$it:1}
A.dk.prototype={
ad(a,b,c){var s=A.iJ(this.a,b,c)
s.$flags=3
return s},
bd(a,b){return this.ad(0,b,null)},
bc(a,b,c){var s=A.iI(this.a,b,c)
s.$flags=3
return s},
$ibC:1}
A.aN.prototype={
gl(a){return B.aQ},
$il:1,
$iaN:1,
$idA:1}
A.C.prototype={
gk(a){return a.length},
$iT:1}
A.bR.prototype={
m(a,b){A.ar(b,a,a.length)
return a[b]},
q(a,b,c){A.dm(c)
a.$flags&2&&A.z(a)
A.ar(b,a,a.length)
a[b]=c},
$ie:1,
$ik:1}
A.U.prototype={
q(a,b,c){A.aa(c)
a.$flags&2&&A.z(a)
A.ar(b,a,a.length)
a[b]=c},
P(a,b,c,d){var s,r,q,p
t.hb.a(d)
a.$flags&2&&A.z(a,5)
if(t.eB.b(d)){s=a.length
this.aU(a,b,s,"start")
this.aU(a,c,s,"end")
if(b>c)A.n(A.a4(b,0,c,null,null))
r=c-b
q=d.length
if(q<r)A.n(A.af("Not enough elements"))
p=q!==r?d.subarray(0,r):d
a.set(p,b)
return}this.bF(a,b,c,d,0)},
$ie:1,
$ik:1}
A.bc.prototype={
gl(a){return B.aR},
$il:1,
$ibc:1,
$idD:1}
A.bd.prototype={
gl(a){return B.aS},
$il:1,
$ibd:1,
$idE:1}
A.be.prototype={
gl(a){return B.aT},
m(a,b){A.ar(b,a,a.length)
return a[b]},
$il:1,
$ibe:1,
$idF:1}
A.bf.prototype={
gl(a){return B.aU},
m(a,b){A.ar(b,a,a.length)
return a[b]},
$il:1,
$ibf:1,
$idG:1}
A.bg.prototype={
gl(a){return B.aV},
m(a,b){A.ar(b,a,a.length)
return a[b]},
$il:1,
$ibg:1,
$idH:1}
A.bh.prototype={
gl(a){return B.aY},
m(a,b){A.ar(b,a,a.length)
return a[b]},
$il:1,
$ibh:1,
$ie1:1}
A.bi.prototype={
gl(a){return B.aZ},
m(a,b){A.ar(b,a,a.length)
return a[b]},
$il:1,
$ibi:1,
$ie2:1}
A.aO.prototype={
gl(a){return B.b_},
gk(a){return a.length},
m(a,b){A.ar(b,a,a.length)
return a[b]},
$il:1,
$iaO:1,
$ie3:1}
A.ay.prototype={
gl(a){return B.b0},
gk(a){return a.length},
m(a,b){A.ar(b,a,a.length)
return a[b]},
a2(a,b,c){return new Uint8Array(a.subarray(b,A.aD(b,c,a.length)))},
$il:1,
$iay:1,
$ian:1}
A.c9.prototype={}
A.ca.prototype={}
A.cb.prototype={}
A.cc.prototype={}
A.a5.prototype={
h(a){return A.cm(v.typeUniverse,this,a)},
C(a){return A.ht(v.typeUniverse,this,a)}}
A.de.prototype={}
A.eE.prototype={
i(a){return A.L(this.a,null)}}
A.dd.prototype={
i(a){return this.a}}
A.ci.prototype={$ial:1}
A.eb.prototype={
$1(a){var s=this.a,r=s.a
s.a=null
r.$0()},
$S:4}
A.ea.prototype={
$1(a){var s,r
this.a.a=t.M.a(a)
s=this.b
r=this.c
s.firstChild?s.removeChild(r):s.appendChild(r)},
$S:13}
A.ec.prototype={
$0(){this.a.$0()},
$S:5}
A.ed.prototype={
$0(){this.a.$0()},
$S:5}
A.eC.prototype={
bG(a,b){if(self.setTimeout!=null)self.setTimeout(A.dt(new A.eD(this,b),0),a)
else throw A.b(A.e4("`setTimeout()` not found."))}}
A.eD.prototype={
$0(){this.b.$0()},
$S:0}
A.c4.prototype={
aD(a){var s,r=this,q=r.$ti
q.h("1/?").a(a)
if(a==null)a=q.c.a(a)
if(!r.b)r.a.a5(a)
else{s=r.a
if(q.h("O<1>").b(a))s.aT(a)
else s.aW(a)}},
bh(a,b){var s=this.a
if(this.b)s.a7(new A.M(a,b))
else s.R(new A.M(a,b))},
$idC:1}
A.eR.prototype={
$1(a){return this.a.$2(0,a)},
$S:14}
A.eS.prototype={
$2(a,b){this.a.$2(1,new A.bH(a,t.l.a(b)))},
$S:15}
A.f_.prototype={
$2(a,b){this.a(A.aa(a),b)},
$S:16}
A.A.prototype={
gv(){var s=this.b
return s==null?this.$ti.c.a(s):s},
c1(a,b){var s,r,q
a=A.aa(a)
b=b
s=this.a
for(;;)try{r=s(this,a,b)
return r}catch(q){b=q
a=1}},
n(){var s,r,q,p,o=this,n=null,m=0
for(;;){s=o.d
if(s!=null)try{if(s.n()){o.b=s.gv()
return!0}else o.d=null}catch(r){n=r
m=1
o.d=null}q=o.c1(m,n)
if(1===q)return!0
if(0===q){o.b=null
p=o.e
if(p==null||p.length===0){o.a=A.ho
return!1}if(0>=p.length)return A.a(p,-1)
o.a=p.pop()
m=0
n=null
continue}if(2===q){m=0
n=null
continue}if(3===q){n=o.c
o.c=null
p=o.e
if(p==null||p.length===0){o.b=null
o.a=A.ho
throw n
return!1}if(0>=p.length)return A.a(p,-1)
o.a=p.pop()
m=1
continue}throw A.b(A.af("sync*"))}return!1},
cA(a){var s,r,q=this
if(a instanceof A.br){s=a.a()
r=q.e
if(r==null)r=q.e=[]
B.a.j(r,q.a)
q.a=s
return 2}else{q.d=J.fe(a)
return 2}},
$iae:1}
A.br.prototype={
gE(a){return new A.A(this.a(),this.$ti.h("A<1>"))}}
A.M.prototype={
i(a){return A.p(this.a)},
$iq:1,
gak(){return this.b}}
A.c6.prototype={
bh(a,b){var s=this.a
if((s.a&30)!==0)throw A.b(A.af("Future already completed"))
s.R(A.jH(a,b))},
$idC:1}
A.bl.prototype={
aD(a){var s,r=this.$ti
r.h("1/?").a(a)
s=this.a
if((s.a&30)!==0)throw A.b(A.af("Future already completed"))
s.a5(r.h("1/").a(a))},
ca(){return this.aD(null)}}
A.ao.prototype={
cl(a){if((this.c&15)!==6)return!0
return this.b.b.aI(t.al.a(this.d),a.a,t.y,t.K)},
cg(a){var s,r=this,q=r.e,p=null,o=t.z,n=t.K,m=a.a,l=r.b.b
if(t.Q.b(q))p=l.cn(q,m,a.b,o,n,t.l)
else p=l.aI(t.v.a(q),m,o,n)
try{o=r.$ti.h("2/").a(p)
return o}catch(s){if(t.eK.b(A.R(s))){if((r.c&1)!==0)throw A.b(A.cz("The error handler of Future.then must return a value of the returned future's type","onError"))
throw A.b(A.cz("The error handler of Future.catchError must return a value of the future's type","onError"))}else throw s}}}
A.j.prototype={
ae(a,b,c){var s,r,q,p=this.$ti
p.C(c).h("1/(2)").a(a)
s=$.i
if(s===B.c){if(b!=null&&!t.Q.b(b)&&!t.v.b(b))throw A.b(A.au(b,"onError",u.c))}else{c.h("@<0/>").C(p.c).h("1(2)").a(a)
if(b!=null)b=A.k7(b,s)}r=new A.j(s,c.h("j<0>"))
q=b==null?1:3
this.a4(new A.ao(r,q,a,b,p.h("@<1>").C(c).h("ao<1,2>")))
return r},
cp(a,b){return this.ae(a,null,b)},
ba(a,b,c){var s,r=this.$ti
r.C(c).h("1/(2)").a(a)
s=new A.j($.i,c.h("j<0>"))
this.a4(new A.ao(s,19,a,b,r.h("@<1>").C(c).h("ao<1,2>")))
return s},
aK(a){var s,r
t.O.a(a)
s=this.$ti
r=new A.j($.i,s)
this.a4(new A.ao(r,8,a,null,s.h("ao<1,1>")))
return r},
c2(a){this.a=this.a&1|16
this.c=a},
a6(a){this.a=a.a&30|this.a&1
this.c=a.c},
a4(a){var s,r=this,q=r.a
if(q<=3){a.a=t.F.a(r.c)
r.c=a}else{if((q&4)!==0){s=t._.a(r.c)
if((s.a&24)===0){s.a4(a)
return}r.a6(s)}A.bt(null,null,r.b,t.M.a(new A.ei(r,a)))}},
b6(a){var s,r,q,p,o,n,m=this,l={}
l.a=a
if(a==null)return
s=m.a
if(s<=3){r=t.F.a(m.c)
m.c=a
if(r!=null){q=a.a
for(p=a;q!=null;p=q,q=o)o=q.a
p.a=r}}else{if((s&4)!==0){n=t._.a(m.c)
if((n.a&24)===0){n.b6(a)
return}m.a6(n)}l.a=m.a9(a)
A.bt(null,null,m.b,t.M.a(new A.em(l,m)))}},
T(){var s=t.F.a(this.c)
this.c=null
return this.a9(s)},
a9(a){var s,r,q
for(s=a,r=null;s!=null;r=s,s=q){q=s.a
s.a=r}return r},
aW(a){var s,r=this
r.$ti.c.a(a)
s=r.T()
r.a=8
r.c=a
A.aW(r,s)},
bL(a){var s,r,q=this
if((a.a&16)!==0){s=q.b===a.b
s=!(s||s)}else s=!1
if(s)return
r=q.T()
q.a6(a)
A.aW(q,r)},
a7(a){var s=this.T()
this.c2(a)
A.aW(this,s)},
bK(a,b){A.ab(a)
t.l.a(b)
this.a7(new A.M(a,b))},
a5(a){var s=this.$ti
s.h("1/").a(a)
if(s.h("O<1>").b(a)){this.aT(a)
return}this.bI(a)},
bI(a){var s=this
s.$ti.c.a(a)
s.a^=2
A.bt(null,null,s.b,t.M.a(new A.ek(s,a)))},
aT(a){A.fq(this.$ti.h("O<1>").a(a),this,!1)
return},
R(a){this.a^=2
A.bt(null,null,this.b,t.M.a(new A.ej(this,a)))},
$iO:1}
A.ei.prototype={
$0(){A.aW(this.a,this.b)},
$S:0}
A.em.prototype={
$0(){A.aW(this.b,this.a.a)},
$S:0}
A.el.prototype={
$0(){A.fq(this.a.a,this.b,!0)},
$S:0}
A.ek.prototype={
$0(){this.a.aW(this.b)},
$S:0}
A.ej.prototype={
$0(){this.a.a7(this.b)},
$S:0}
A.ep.prototype={
$0(){var s,r,q,p,o,n,m,l,k=this,j=null
try{q=k.a.a
j=q.b.b.br(t.O.a(q.d),t.z)}catch(p){s=A.R(p)
r=A.Y(p)
if(k.c&&t.n.a(k.b.a.c).a===s){q=k.a
q.c=t.n.a(k.b.a.c)}else{q=s
o=r
if(o==null)o=A.dz(q)
n=k.a
n.c=new A.M(q,o)
q=n}q.b=!0
return}if(j instanceof A.j&&(j.a&24)!==0){if((j.a&16)!==0){q=k.a
q.c=t.n.a(j.c)
q.b=!0}return}if(j instanceof A.j){m=k.b.a
l=new A.j(m.b,m.$ti)
j.ae(new A.eq(l,m),new A.er(l),t.H)
q=k.a
q.c=l
q.b=!1}},
$S:0}
A.eq.prototype={
$1(a){this.a.bL(this.b)},
$S:4}
A.er.prototype={
$2(a,b){A.ab(a)
t.l.a(b)
this.a.a7(new A.M(a,b))},
$S:7}
A.eo.prototype={
$0(){var s,r,q,p,o,n,m,l
try{q=this.a
p=q.a
o=p.$ti
n=o.c
m=n.a(this.b)
q.c=p.b.b.aI(o.h("2/(1)").a(p.d),m,o.h("2/"),n)}catch(l){s=A.R(l)
r=A.Y(l)
q=s
p=r
if(p==null)p=A.dz(q)
o=this.a
o.c=new A.M(q,p)
o.b=!0}},
$S:0}
A.en.prototype={
$0(){var s,r,q,p,o,n,m,l=this
try{s=t.n.a(l.a.a.c)
p=l.b
if(p.a.cl(s)&&p.a.e!=null){p.c=p.a.cg(s)
p.b=!1}}catch(o){r=A.R(o)
q=A.Y(o)
p=t.n.a(l.a.a.c)
if(p.a===r){n=l.b
n.c=p
p=n}else{p=r
n=q
if(n==null)n=A.dz(p)
m=l.b
m.c=new A.M(p,n)
p=m}p.b=!0}},
$S:0}
A.d4.prototype={}
A.c0.prototype={
gk(a){var s={},r=new A.j($.i,t.fJ)
s.a=0
this.bo(new A.dX(s,this),!0,new A.dY(s,r),r.gbJ())
return r}}
A.dX.prototype={
$1(a){this.b.$ti.c.a(a);++this.a.a},
$S(){return this.b.$ti.h("~(1)")}}
A.dY.prototype={
$0(){var s=this.b,r=s.$ti,q=r.h("1/").a(this.a.a),p=s.T()
r.c.a(q)
s.a=8
s.c=q
A.aW(s,p)},
$S:0}
A.cf.prototype={
gbZ(){var s,r=this
if((r.b&8)===0)return A.B(r).h("a8<1>?").a(r.a)
s=A.B(r)
return s.h("a8<1>?").a(s.h("cg<1>").a(r.a).gaA())},
aY(){var s,r,q=this
if((q.b&8)===0){s=q.a
if(s==null)s=q.a=new A.a8(A.B(q).h("a8<1>"))
return A.B(q).h("a8<1>").a(s)}r=A.B(q)
s=r.h("cg<1>").a(q.a).gaA()
return r.h("a8<1>").a(s)},
gb8(){var s=this.a
if((this.b&8)!==0)s=t.fv.a(s).gaA()
return A.B(this).h("bo<1>").a(s)},
aR(){if((this.b&4)!==0)return new A.az("Cannot add event after closing")
return new A.az("Cannot add event while adding a stream")},
aX(){var s=this.c
if(s==null)s=this.c=(this.b&2)!==0?$.fc():new A.j($.i,t.D)
return s},
j(a,b){var s,r=this,q=A.B(r)
q.c.a(b)
s=r.b
if(s>=4)throw A.b(r.aR())
if((s&1)!==0)r.aw(b)
else if((s&3)===0)r.aY().j(0,new A.aU(b,q.h("aU<1>")))},
u(){var s=this,r=s.b
if((r&4)!==0)return s.aX()
if(r>=4)throw A.b(s.aR())
r=s.b=r|4
if((r&1)!==0)s.az()
else if((r&3)===0)s.aY().j(0,B.A)
return s.aX()},
c6(a,b,c,d){var s,r,q,p,o,n,m,l=this,k=A.B(l)
k.h("~(1)?").a(a)
t.b.a(c)
if((l.b&3)!==0)throw A.b(A.af("Stream has already been listened to."))
s=$.i
r=d?1:0
q=b!=null?32:0
t.V.C(k.c).h("1(2)").a(a)
A.j1(s,b)
p=t.M
o=new A.bo(l,a,p.a(c),s,r|q,k.h("bo<1>"))
n=l.gbZ()
if(((l.b|=1)&8)!==0){m=k.h("cg<1>").a(l.a)
m.saA(o)
m.cm()}else l.a=o
o.c3(n)
k=p.a(new A.eB(l))
s=o.e
o.e=s|64
k.$0()
o.e&=4294967231
o.aV((s&4)!==0)
return o},
c_(a){var s,r,q,p,o,n,m,l,k=this,j=A.B(k)
j.h("cY<1>").a(a)
s=null
if((k.b&8)!==0)s=j.h("cg<1>").a(k.a).cB()
k.a=null
k.b=k.b&4294967286|2
r=k.r
if(r!=null)if(s==null)try{q=r.$0()
if(q instanceof A.j)s=q}catch(n){p=A.R(n)
o=A.Y(n)
m=new A.j($.i,t.D)
j=A.ab(p)
l=t.l.a(o)
m.R(new A.M(j,l))
s=m}else s=s.aK(r)
j=new A.eA(k)
if(s!=null)s=s.aK(j)
else j.$0()
return s},
$iha:1,
$ihn:1,
$iaV:1}
A.eB.prototype={
$0(){A.fA(this.a.d)},
$S:0}
A.eA.prototype={
$0(){var s=this.a.c
if(s!=null&&(s.a&30)===0)s.a5(null)},
$S:0}
A.d5.prototype={
aw(a){var s=this.$ti
s.c.a(a)
this.gb8().aP(new A.aU(a,s.h("aU<1>")))},
az(){this.gb8().aP(B.A)}}
A.bm.prototype={}
A.bn.prototype={
gp(a){return(A.bV(this.a)^892482866)>>>0},
K(a,b){if(b==null)return!1
if(this===b)return!0
return b instanceof A.bn&&b.a===this.a}}
A.bo.prototype={
b2(){return this.w.c_(this)},
b3(){var s=this.w,r=A.B(s)
r.h("cY<1>").a(this)
if((s.b&8)!==0)r.h("cg<1>").a(s.a).cC()
A.fA(s.e)},
b4(){var s=this.w,r=A.B(s)
r.h("cY<1>").a(this)
if((s.b&8)!==0)r.h("cg<1>").a(s.a).cm()
A.fA(s.f)}}
A.c5.prototype={
c3(a){var s=this
A.B(s).h("a8<1>?").a(a)
if(a==null)return
s.r=a
if(a.c!=null){s.e|=128
a.ai(s)}},
aS(){var s,r=this,q=r.e|=8
if((q&128)!==0){s=r.r
if(s.a===1)s.a=3}if((q&64)===0)r.r=null
r.f=r.b2()},
b3(){},
b4(){},
b2(){return null},
aP(a){var s,r=this,q=r.r
if(q==null)q=r.r=new A.a8(A.B(r).h("a8<1>"))
q.j(0,a)
s=r.e
if((s&128)===0){s|=128
r.e=s
if(s<256)q.ai(r)}},
aw(a){var s,r=this,q=A.B(r).c
q.a(a)
s=r.e
r.e=s|64
r.d.co(r.a,a,q)
r.e&=4294967231
r.aV((s&4)!==0)},
az(){var s,r=this,q=new A.ee(r)
r.aS()
r.e|=16
s=r.f
if(s!=null&&s!==$.fc())s.aK(q)
else q.$0()},
aV(a){var s,r,q=this,p=q.e
if((p&128)!==0&&q.r.c==null){p=q.e=p&4294967167
s=!1
if((p&4)!==0)if(p<256){s=q.r
s=s==null?null:s.c==null
s=s!==!1}if(s){p&=4294967291
q.e=p}}for(;;a=r){if((p&8)!==0){q.r=null
return}r=(p&4)!==0
if(a===r)break
q.e=p^64
if(r)q.b3()
else q.b4()
p=q.e&=4294967231}if((p&128)!==0&&p<256)q.r.ai(q)},
$icY:1,
$iaV:1}
A.ee.prototype={
$0(){var s=this.a,r=s.e
if((r&16)===0)return
s.e=r|74
s.d.bs(s.c)
s.e&=4294967231},
$S:0}
A.ch.prototype={
bo(a,b,c,d){var s=this.$ti
s.h("~(1)?").a(a)
t.b.a(c)
return this.a.c6(s.h("~(1)?").a(a),d,c,b===!0)},
ck(a,b){return this.bo(a,null,b,null)}}
A.aB.prototype={
sa0(a){this.a=t.ev.a(a)},
ga0(){return this.a}}
A.aU.prototype={
bp(a){this.$ti.h("aV<1>").a(a).aw(this.b)}}
A.da.prototype={
bp(a){a.az()},
ga0(){return null},
sa0(a){throw A.b(A.af("No events after a done."))},
$iaB:1}
A.a8.prototype={
ai(a){var s,r=this
r.$ti.h("aV<1>").a(a)
s=r.a
if(s===1)return
if(s>=1){r.a=1
return}A.kQ(new A.ex(r,a))
r.a=1},
j(a,b){var s=this,r=s.c
if(r==null)s.b=s.c=b
else{r.sa0(b)
s.c=b}}}
A.ex.prototype={
$0(){var s,r,q,p=this.a,o=p.a
p.a=0
if(o===3)return
s=p.$ti.h("aV<1>").a(this.b)
r=p.b
q=r.ga0()
p.b=q
if(q==null)p.c=null
r.bp(s)},
$S:0}
A.di.prototype={}
A.co.prototype={$ihf:1}
A.dh.prototype={
bs(a){var s,r,q
t.M.a(a)
try{if(B.c===$.i){a.$0()
return}A.hM(null,null,this,a,t.H)}catch(q){s=A.R(q)
r=A.Y(q)
A.dp(A.ab(s),t.l.a(r))}},
co(a,b,c){var s,r,q
c.h("~(0)").a(a)
c.a(b)
try{if(B.c===$.i){a.$1(b)
return}A.hN(null,null,this,a,b,t.H,c)}catch(q){s=A.R(q)
r=A.Y(q)
A.dp(A.ab(s),t.l.a(r))}},
be(a){return new A.ez(this,t.M.a(a))},
br(a,b){b.h("0()").a(a)
if($.i===B.c)return a.$0()
return A.hM(null,null,this,a,b)},
aI(a,b,c,d){c.h("@<0>").C(d).h("1(2)").a(a)
d.a(b)
if($.i===B.c)return a.$1(b)
return A.hN(null,null,this,a,b,c,d)},
cn(a,b,c,d,e,f){d.h("@<0>").C(e).C(f).h("1(2,3)").a(a)
e.a(b)
f.a(c)
if($.i===B.c)return a.$2(b,c)
return A.k9(null,null,this,a,b,c,d,e,f)},
aH(a,b,c,d){return b.h("@<0>").C(c).C(d).h("1(2,3)").a(a)}}
A.ez.prototype={
$0(){return this.a.bs(this.b)},
$S:0}
A.eX.prototype={
$0(){A.iu(this.a,this.b)},
$S:0}
A.c7.prototype={
gE(a){var s=this,r=new A.c8(s,s.r,s.$ti.h("c8<1>"))
r.c=s.e
return r},
gk(a){return this.a},
cb(a,b){var s
if((b&1073741823)===b){s=this.c
if(s==null)return!1
return t.R.a(s[b])!=null}else return this.bN(b)},
bN(a){var s=this.d
if(s==null)return!1
return this.aZ(s[B.b.gp(a)&1073741823],a)>=0},
j(a,b){var s,r,q=this
q.$ti.c.a(b)
if(typeof b=="string"&&b!=="__proto__"){s=q.b
return q.aO(s==null?q.b=A.fr():s,b)}else if(typeof b=="number"&&(b&1073741823)===b){r=q.c
return q.aO(r==null?q.c=A.fr():r,b)}else return q.bH(b)},
bH(a){var s,r,q,p=this
p.$ti.c.a(a)
s=p.d
if(s==null)s=p.d=A.fr()
r=J.P(a)&1073741823
q=s[r]
if(q==null)s[r]=[p.au(a)]
else{if(p.aZ(q,a)>=0)return!1
q.push(p.au(a))}return!0},
aO(a,b){this.$ti.c.a(b)
if(t.R.a(a[b])!=null)return!1
a[b]=this.au(b)
return!0},
au(a){var s=this,r=new A.df(s.$ti.c.a(a))
if(s.e==null)s.e=s.f=r
else s.f=s.f.b=r;++s.a
s.r=s.r+1&1073741823
return r},
aZ(a,b){var s,r
if(a==null)return-1
s=a.length
for(r=0;r<s;++r)if(J.cv(a[r].a,b))return r
return-1}}
A.df.prototype={}
A.c8.prototype={
gv(){var s=this.d
return s==null?this.$ti.c.a(s):s},
n(){var s=this,r=s.c,q=s.a
if(s.b!==q.r)throw A.b(A.bD(q))
else if(r==null){s.d=null
return!1}else{s.d=s.$ti.h("1?").a(r.a)
s.c=r.b
return!0}},
$iae:1}
A.h.prototype={
gE(a){return new A.aL(a,this.gk(a),A.at(a).h("aL<h.E>"))},
V(a,b){return this.m(a,b)},
gbn(a){return this.gk(a)!==0},
aj(a,b){return A.cZ(a,b,null,A.at(a).h("h.E"))},
bt(a,b){return A.cZ(a,0,A.ds(b,"count",t.S),A.at(a).h("h.E"))},
bB(a,b,c,d,e){var s,r,q
A.at(a).h("e<h.E>").a(d)
A.bY(b,c,this.gk(a))
s=c-b
if(s===0)return
A.bX(e,"skipCount")
r=J.ct(d)
if(e+s>r.gk(d))throw A.b(A.af("Too few elements"))
if(e<b)for(q=s-1;q>=0;--q)this.q(a,b+q,r.m(d,e+q))
else for(q=0;q<s;++q)this.q(a,b+q,r.m(d,e+q))},
i(a){return A.fi(a,"[","]")},
$ie:1,
$ik:1}
A.Q.prototype={
W(a,b){var s,r,q,p=A.B(this)
p.h("~(Q.K,Q.V)").a(b)
for(s=this.gaG(),s=s.gE(s),p=p.h("Q.V");s.n();){r=s.gv()
q=this.m(0,r)
b.$2(r,q==null?p.a(q):q)}},
gk(a){var s=this.gaG()
return s.gk(s)},
gZ(a){var s=this.gaG()
return s.gZ(s)},
i(a){return A.h0(this)},
$idL:1}
A.dM.prototype={
$2(a,b){var s,r=this.a
if(!r.a)this.b.a+=", "
r.a=!1
r=this.b
s=A.p(a)
r.a=(r.a+=s)+": "
s=A.p(b)
r.a+=s},
$S:1}
A.bj.prototype={
i(a){return A.fi(this,"{","}")},
$ie:1}
A.cd.prototype={}
A.eI.prototype={
$0(){var s,r
try{s=new TextDecoder("utf-8",{fatal:true})
return s}catch(r){}return null},
$S:8}
A.eH.prototype={
$0(){var s,r
try{s=new TextDecoder("utf-8",{fatal:false})
return s}catch(r){}return null},
$S:8}
A.cF.prototype={}
A.cH.prototype={}
A.bN.prototype={
i(a){var s=A.cJ(this.a)
return(this.b!=null?"Converting object to an encodable object failed:":"Converting object did not return an encodable object:")+" "+s}}
A.cR.prototype={
i(a){return"Cyclic error in JSON stringify"}}
A.cQ.prototype={
ce(a,b){var s=A.j4(a,this.gcf().b,null)
return s},
gcf(){return B.aE}}
A.dJ.prototype={}
A.eu.prototype={
bz(a){var s,r,q,p,o,n,m=a.length
for(s=this.c,r=0,q=0;q<m;++q){p=a.charCodeAt(q)
if(p>92){if(p>=55296){o=p&64512
if(o===55296){n=q+1
n=!(n<m&&(a.charCodeAt(n)&64512)===56320)}else n=!1
if(!n)if(o===56320){o=q-1
o=!(o>=0&&(a.charCodeAt(o)&64512)===55296)}else o=!1
else o=!0
if(o){if(q>r)s.a+=B.m.a3(a,r,q)
r=q+1
o=A.v(92)
s.a+=o
o=A.v(117)
s.a+=o
o=A.v(100)
s.a+=o
o=p>>>8&15
o=A.v(o<10?48+o:87+o)
s.a+=o
o=p>>>4&15
o=A.v(o<10?48+o:87+o)
s.a+=o
o=p&15
o=A.v(o<10?48+o:87+o)
s.a+=o}}continue}if(p<32){if(q>r)s.a+=B.m.a3(a,r,q)
r=q+1
o=A.v(92)
s.a+=o
switch(p){case 8:o=A.v(98)
s.a+=o
break
case 9:o=A.v(116)
s.a+=o
break
case 10:o=A.v(110)
s.a+=o
break
case 12:o=A.v(102)
s.a+=o
break
case 13:o=A.v(114)
s.a+=o
break
default:o=A.v(117)
s.a+=o
o=A.v(48)
s.a=(s.a+=o)+o
o=p>>>4&15
o=A.v(o<10?48+o:87+o)
s.a+=o
o=p&15
o=A.v(o<10?48+o:87+o)
s.a+=o
break}}else if(p===34||p===92){if(q>r)s.a+=B.m.a3(a,r,q)
r=q+1
o=A.v(92)
s.a+=o
o=A.v(p)
s.a+=o}}if(r===0)s.a+=a
else if(r<m)s.a+=B.m.a3(a,r,m)},
an(a){var s,r,q,p
for(s=this.a,r=s.length,q=0;q<r;++q){p=s[q]
if(a==null?p==null:a===p)throw A.b(new A.cR(a,null))}B.a.j(s,a)},
ah(a){var s,r,q,p,o=this
if(o.by(a))return
o.an(a)
try{s=o.b.$1(a)
if(!o.by(s)){q=A.fW(a,null,o.gb5())
throw A.b(q)}q=o.a
if(0>=q.length)return A.a(q,-1)
q.pop()}catch(p){r=A.R(p)
q=A.fW(a,r,o.gb5())
throw A.b(q)}},
by(a){var s,r,q=this
if(typeof a=="number"){if(!isFinite(a))return!1
q.c.a+=B.I.i(a)
return!0}else if(a===!0){q.c.a+="true"
return!0}else if(a===!1){q.c.a+="false"
return!0}else if(a==null){q.c.a+="null"
return!0}else if(typeof a=="string"){s=q.c
s.a+='"'
q.bz(a)
s.a+='"'
return!0}else if(t.j.b(a)){q.an(a)
q.ct(a)
s=q.a
if(0>=s.length)return A.a(s,-1)
s.pop()
return!0}else if(a instanceof A.Q){q.an(a)
r=q.cu(a)
s=q.a
if(0>=s.length)return A.a(s,-1)
s.pop()
return r}else return!1},
ct(a){var s,r,q=this.c
q.a+="["
s=J.dv(a)
if(s.gbn(a)){this.ah(s.m(a,0))
for(r=1;r<s.gk(a);++r){q.a+=","
this.ah(s.m(a,r))}}q.a+="]"},
cu(a){var s,r,q,p,o,n,m=this,l={}
if(a.gZ(a)){m.c.a+="{}"
return!0}s=a.gk(a)*2
r=A.aM(s,null,!1,t.X)
q=l.a=0
l.b=!0
a.W(0,new A.ev(l,r))
if(!l.b)return!1
p=m.c
p.a+="{"
for(o='"';q<s;q+=2,o=',"'){p.a+=o
m.bz(A.aq(r[q]))
p.a+='":'
n=q+1
if(!(n<s))return A.a(r,n)
m.ah(r[n])}p.a+="}"
return!0}}
A.ev.prototype={
$2(a,b){var s,r
if(typeof a!="string")this.a.b=!1
s=this.b
r=this.a
B.a.q(s,r.a++,a)
B.a.q(s,r.a++,b)},
$S:1}
A.et.prototype={
gb5(){var s=this.c.a
return s.charCodeAt(0)==0?s:s}}
A.e6.prototype={
J(a){var s,r,q,p=a.length,o=A.bY(0,null,p)
if(o===0)return new Uint8Array(0)
s=new Uint8Array(o*3)
r=new A.eJ(s)
if(r.bT(a,0,o)!==o){q=o-1
if(!(q>=0&&q<p))return A.a(a,q)
r.aB()}return B.d.a2(s,0,r.b)}}
A.eJ.prototype={
aB(){var s,r=this,q=r.c,p=r.b,o=r.b=p+1
q.$flags&2&&A.z(q)
s=q.length
if(!(p<s))return A.a(q,p)
q[p]=239
p=r.b=o+1
if(!(o<s))return A.a(q,o)
q[o]=191
r.b=p+1
if(!(p<s))return A.a(q,p)
q[p]=189},
c7(a,b){var s,r,q,p,o,n=this
if((b&64512)===56320){s=65536+((a&1023)<<10)|b&1023
r=n.c
q=n.b
p=n.b=q+1
r.$flags&2&&A.z(r)
o=r.length
if(!(q<o))return A.a(r,q)
r[q]=s>>>18|240
q=n.b=p+1
if(!(p<o))return A.a(r,p)
r[p]=s>>>12&63|128
p=n.b=q+1
if(!(q<o))return A.a(r,q)
r[q]=s>>>6&63|128
n.b=p+1
if(!(p<o))return A.a(r,p)
r[p]=s&63|128
return!0}else{n.aB()
return!1}},
bT(a,b,c){var s,r,q,p,o,n,m,l,k=this
if(b!==c){s=c-1
if(!(s>=0&&s<a.length))return A.a(a,s)
s=(a.charCodeAt(s)&64512)===55296}else s=!1
if(s)--c
for(s=k.c,r=s.$flags|0,q=s.length,p=a.length,o=b;o<c;++o){if(!(o<p))return A.a(a,o)
n=a.charCodeAt(o)
if(n<=127){m=k.b
if(m>=q)break
k.b=m+1
r&2&&A.z(s)
s[m]=n}else{m=n&64512
if(m===55296){if(k.b+4>q)break
m=o+1
if(!(m<p))return A.a(a,m)
if(k.c7(n,a.charCodeAt(m)))o=m}else if(m===56320){if(k.b+3>q)break
k.aB()}else if(n<=2047){m=k.b
l=m+1
if(l>=q)break
k.b=l
r&2&&A.z(s)
if(!(m<q))return A.a(s,m)
s[m]=n>>>6|192
k.b=l+1
s[l]=n&63|128}else{m=k.b
if(m+2>=q)break
l=k.b=m+1
r&2&&A.z(s)
if(!(m<q))return A.a(s,m)
s[m]=n>>>12|224
m=k.b=l+1
if(!(l<q))return A.a(s,l)
s[l]=n>>>6&63|128
k.b=m+1
if(!(m<q))return A.a(s,m)
s[m]=n&63|128}}}return o}}
A.e5.prototype={
J(a){return new A.eG(this.a).bP(t.L.a(a),0,null,!0)}}
A.eG.prototype={
bP(a,b,c,d){var s,r,q,p,o,n,m,l=this
t.L.a(a)
s=A.bY(b,c,a.length)
if(b===s)return""
if(a instanceof Uint8Array){r=a
q=r
p=0}else{q=A.jm(a,b,s)
s-=b
p=b
b=0}if(s-b>=15){o=l.a
n=A.jl(o,q,b,s)
if(n!=null){if(!o)return n
if(n.indexOf("\ufffd")<0)return n}}n=l.ao(q,b,s,!0)
o=l.b
if((o&1)!==0){m=A.jn(o)
l.b=0
throw A.b(A.a3(m,a,p+l.c))}return n},
ao(a,b,c,d){var s,r,q=this
if(c-b>1000){s=B.b.F(b+c,2)
r=q.ao(a,b,s,!1)
if((q.b&1)!==0)return r
return r+q.ao(a,s,c,d)}return q.cc(a,b,c,d)},
cc(a,b,a0,a1){var s,r,q,p,o,n,m,l,k=this,j="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFFFFFFFFFFFFFFFFGGGGGGGGGGGGGGGGHHHHHHHHHHHHHHHHHHHHHHHHHHHIHHHJEEBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBKCCCCCCCCCCCCDCLONNNMEEEEEEEEEEE",i=" \x000:XECCCCCN:lDb \x000:XECCCCCNvlDb \x000:XECCCCCN:lDb AAAAA\x00\x00\x00\x00\x00AAAAA00000AAAAA:::::AAAAAGG000AAAAA00KKKAAAAAG::::AAAAA:IIIIAAAAA000\x800AAAAA\x00\x00\x00\x00 AAAAA",h=65533,g=k.b,f=k.c,e=new A.aQ(""),d=b+1,c=a.length
if(!(b>=0&&b<c))return A.a(a,b)
s=a[b]
A:for(r=k.a;;){for(;;d=o){if(!(s>=0&&s<256))return A.a(j,s)
q=j.charCodeAt(s)&31
f=g<=32?s&61694>>>q:(s&63|f<<6)>>>0
p=g+q
if(!(p>=0&&p<144))return A.a(i,p)
g=i.charCodeAt(p)
if(g===0){p=A.v(f)
e.a+=p
if(d===a0)break A
break}else if((g&1)!==0){if(r)switch(g){case 69:case 67:p=A.v(h)
e.a+=p
break
case 65:p=A.v(h)
e.a+=p;--d
break
default:p=A.v(h)
e.a=(e.a+=p)+p
break}else{k.b=g
k.c=d-1
return""}g=0}if(d===a0)break A
o=d+1
if(!(d>=0&&d<c))return A.a(a,d)
s=a[d]}o=d+1
if(!(d>=0&&d<c))return A.a(a,d)
s=a[d]
if(s<128){for(;;){if(!(o<a0)){n=a0
break}m=o+1
if(!(o>=0&&o<c))return A.a(a,o)
s=a[o]
if(s>=128){n=m-1
o=m
break}o=m}if(n-d<20)for(l=d;l<n;++l){if(!(l<c))return A.a(a,l)
p=A.v(a[l])
e.a+=p}else{p=A.fn(a,d,n)
e.a+=p}if(n===a0)break A
d=o}else d=o}if(a1&&g>32)if(r){c=A.v(h)
e.a+=c}else{k.b=77
k.c=a0
return""}k.b=g
k.c=f
c=e.a
return c.charCodeAt(0)==0?c:c}}
A.dc.prototype={
i(a){return this.L()},
$iaH:1}
A.q.prototype={
gak(){return A.iM(this)}}
A.cA.prototype={
i(a){var s=this.a
if(s!=null)return"Assertion failed: "+A.cJ(s)
return"Assertion failed"}}
A.al.prototype={}
A.a1.prototype={
gaq(){return"Invalid argument"+(!this.a?"(s)":"")},
gap(){return""},
i(a){var s=this,r=s.c,q=r==null?"":" ("+r+")",p=s.d,o=p==null?"":": "+A.p(p),n=s.gaq()+q+o
if(!s.a)return n
return n+s.gap()+": "+A.cJ(s.gaE())},
gaE(){return this.b}}
A.bW.prototype={
gaE(){return A.hA(this.b)},
gaq(){return"RangeError"},
gap(){var s,r=this.e,q=this.f
if(r==null)s=q!=null?": Not less than or equal to "+A.p(q):""
else if(q==null)s=": Not greater than or equal to "+A.p(r)
else if(q>r)s=": Not in inclusive range "+A.p(r)+".."+A.p(q)
else s=q<r?": Valid value range is empty":": Only valid value is "+A.p(r)
return s}}
A.cK.prototype={
gaE(){return A.aa(this.b)},
gaq(){return"RangeError"},
gap(){if(A.aa(this.b)<0)return": index must not be negative"
var s=this.f
if(s===0)return": no indices are valid"
return": index should be less than "+s},
gk(a){return this.f}}
A.c3.prototype={
i(a){return"Unsupported operation: "+this.a}}
A.d1.prototype={
i(a){return"UnimplementedError: "+this.a}}
A.az.prototype={
i(a){return"Bad state: "+this.a}}
A.cG.prototype={
i(a){var s=this.a
if(s==null)return"Concurrent modification during iteration."
return"Concurrent modification during iteration: "+A.cJ(s)+"."}}
A.c_.prototype={
i(a){return"Stack Overflow"},
gak(){return null},
$iq:1}
A.eh.prototype={
i(a){return"Exception: "+this.a}}
A.bI.prototype={
i(a){var s=this.a,r=""!==s?"FormatException: "+s:"FormatException",q=this.c
return q!=null?r+(" (at offset "+A.p(q)+")"):r}}
A.e.prototype={
gk(a){var s,r=this.gE(this)
for(s=0;r.n();)++s
return s},
V(a,b){var s,r
A.bX(b,"index")
s=this.gE(this)
for(r=b;s.n();){if(r===0)return s.gv();--r}throw A.b(A.fh(b,b-r,this,"index"))},
i(a){return A.iw(this,"(",")")}}
A.u.prototype={
gp(a){return A.d.prototype.gp.call(this,0)},
i(a){return"null"}}
A.d.prototype={$id:1,
K(a,b){return this===b},
gp(a){return A.bV(this)},
i(a){return"Instance of '"+A.cT(this)+"'"},
gl(a){return A.fH(this)},
toString(){return this.i(this)}}
A.dj.prototype={
i(a){return""},
$ia6:1}
A.aQ.prototype={
gk(a){return this.a.length},
i(a){var s=this.a
return s.charCodeAt(0)==0?s:s},
$iiS:1}
A.e9.prototype={}
A.dy.prototype={
a8(){var s,r,q,p,o,n,m,l,k,j,i=this,h=null
for(s=i.c,r=i.b,q=r.length;;){p=i.e
if(p+7>s.byteLength)return h
o=!1
if(p+128===q){if(!(p>=0&&p<q))return A.a(r,p)
if(r[p]===84){n=p+1
if(!(n<q))return A.a(r,n)
if(r[n]===65){o=p+2
if(!(o<q))return A.a(r,o)
o=r[o]===71}}}if(o)return h
m=A.cu(r,p)
if(m>0&&i.e+m<=q){i.e+=m
continue}l=A.eV(s,i.e)
if(l!=null){r=i.e
q=l.a
if(r+q>s.byteLength)return h
i.w=q
return l}k=i.e
j=A.k8(s,k+1)
if(j<0)return h
i.e=j
p=i.f
o=i.w
i.f=p+(o>0?B.b.t(j-k+(o/2|0),o):0)}},
B(){var s=0,r=A.G(t.a),q,p=this,o,n,m,l,k,j,i,h
var $async$B=A.H(function(a,b){if(a===1)return A.D(b,r)
for(;;)switch(s){case 0:if(p.r)A.n(B.G)
o=p.a8()
if(o==null){q=null
s=1
break}n=p.e
m=o.d
l=o.a
k=l-m
j=new Uint8Array(k)
i=p.c
B.d.P(j,0,k,J.fd(B.j.gI(i),i.byteOffset+(n+m)))
n=p.d
m=n>0
h=m?B.b.t(p.f*1024*1e6,n):0
p.e+=l;++p.f
q=new A.ai(j,h,h,m?B.b.t(1024e6,n):0,!0,0)
s=1
break
case 1:return A.E(q,r)}})
return A.F($async$B,r)},
A(a){var s=0,r=A.G(t.H),q=this,p,o,n
var $async$A=A.H(function(b,c){if(b===1)return A.D(c,r)
for(;;)switch(s){case 0:if(q.r)A.n(B.G)
q.e=A.ff(q.b)
q.f=0
p=q.d
o=p>0?B.b.F(B.b.F(a*p,1e6),1024):0
for(p=0;p<o;){n=q.a8()
if(n==null)break
p=q.f
if(p>=o)break
q.e=q.e+n.a;++p
q.f=p}return A.E(null,r)}})
return A.F($async$A,r)},
gU(){var s,r,q,p,o,n,m=this,l=m.x
if(l!=null)return l
s=m.d
if(s<=0)return null
r=m.e
q=m.f
p=m.w
m.e=A.ff(m.b)
m.f=0
for(o=m.a8();o!=null;o=m.a8()){m.e=m.e+o.a;++m.f}n=m.f
m.e=r
m.f=q
m.w=p
return m.x=B.b.t(n*1024*1e6,s)},
ga_(){return!0},
u(){var s=0,r=A.G(t.H),q,p=this
var $async$u=A.H(function(a,b){if(a===1)return A.D(b,r)
for(;;)switch(s){case 0:q=p.r=!0
s=1
break
case 1:return A.E(q,r)}})
return A.F($async$u,r)},
ga1(){return this.a}}
A.ew.prototype={}
A.bQ.prototype={}
A.dO.prototype={
B(){var s=0,r=A.G(t.a),q,p=this,o,n,m,l,k,j
var $async$B=A.H(function(a,b){if(a===1)return A.D(b,r)
for(;;)switch(s){case 0:if(p.Q)A.n(B.C)
o=p.z
n=p.c
if(o>=n.length){q=null
s=1
break}m=n[o]
n=p.d
if(!(o<n.length)){q=A.a(n,o)
s=1
break}l=B.d.a2(p.b,m,m+n[o])
o=p.e
n=p.z
if(!(n<o.length)){q=A.a(o,n)
s=1
break}k=p.f
j=B.b.t(o[n]*1e6,k)
p.z=n+1
q=new A.ai(l,j,j,B.b.t(p.r*1e6,k),!0,0)
s=1
break
case 1:return A.E(q,r)}})
return A.F($async$B,r)},
A(a){var s=0,r=A.G(t.H),q,p=this,o,n,m,l,k,j,i,h
var $async$A=A.H(function(b,c){if(b===1)return A.D(c,r)
for(;;)A:switch(s){case 0:if(p.Q)A.n(B.C)
o=a<=0?0:a
n=p.e
m=n.length
l=m-1
for(k=p.f,j=0,i=0;j<=l;){h=B.b.H(j+l,1)
if(!(h<m)){q=A.a(n,h)
s=1
break A}if(B.b.t(n[h]*1e6,k)<=o){j=h+1
i=h}else l=h-1}p.z=i
case 1:return A.E(q,r)}})
return A.F($async$A,r)},
gU(){var s=this.e,r=s.length,q=r-1
if(!(q>=0))return A.a(s,q)
return B.b.t((s[q]+this.r)*1e6,this.f)},
ga_(){return!0},
u(){var s=0,r=A.G(t.H),q,p=this
var $async$u=A.H(function(a,b){if(a===1)return A.D(b,r)
for(;;)switch(s){case 0:q=p.Q=!0
s=1
break
case 1:return A.E(q,r)}})
return A.F($async$u,r)},
ga1(){return this.a}}
A.d6.prototype={}
A.ap.prototype={}
A.dP.prototype={
B(){var s=0,r=A.G(t.a),q,p=this,o,n,m,l
var $async$B=A.H(function(a,b){if(a===1)return A.D(b,r)
for(;;)switch(s){case 0:if(p.e)A.n(B.D)
o=p.d
n=p.c
if(o>=n.length){q=null
s=1
break}p.d=o+1
m=n[o]
o=m.b
n=o+m.c
l=p.b
if(n>l.length){q=null
s=1
break}q=new A.ai(new Uint8Array(A.K(A.d0(l,o,n))),m.e,m.d,0,m.r,m.a)
s=1
break
case 1:return A.E(q,r)}})
return A.F($async$B,r)},
A(a){var s=0,r=A.G(t.H),q,p=this,o,n,m,l,k,j,i,h,g,f,e
var $async$A=A.H(function(b,c){if(b===1)return A.D(c,r)
for(;;)A:switch(s){case 0:if(p.e)A.n(B.D)
o=p.a
n=B.a.c8(o,new A.dS())
for(m=p.c,l=m.length,k=o.length,j=0,i=-1,h=0;h<l;++h){g=m[h]
if(!g.r||g.e>a)continue
if(n){f=g.a
if(!(f<k)){q=A.a(o,f)
s=1
break A}f=!(o[f] instanceof A.aA)}else f=!1
if(f)continue
e=g.e
if(e>i){i=e
j=h}}p.d=j
case 1:return A.E(q,r)}})
return A.F($async$A,r)},
gU(){var s,r,q,p,o=this.c,n=o.length
if(n===0)return null
for(s=0,r=0;r<n;++r){q=o[r]
p=q.e+q.f
if(p>s)s=p}return s},
ga_(){return!0},
u(){var s=0,r=A.G(t.H),q,p=this
var $async$u=A.H(function(a,b){if(a===1)return A.D(b,r)
for(;;)switch(s){case 0:q=p.e=!0
s=1
break
case 1:return A.E(q,r)}})
return A.F($async$u,r)},
ga1(){return this.a}}
A.dR.prototype={
$2(a,b){var s=t.bf
return s.a(a).b-s.a(b).b},
$S:17}
A.dQ.prototype={
$1(a){return B.b.t(a*1e6,this.a.a)},
$S:9}
A.dS.prototype={
$1(a){return t.ff.a(a) instanceof A.aA},
$S:18}
A.d8.prototype={}
A.eQ.prototype={
$1(a){var s,r,q,p,o,n,m
for(s=this.b,r=s.length,q=this.a,p=0,o=0;o<a;++o){n=q.a
m=n>>>3
if(m>=r)return-1
p=(p<<1|B.b.c4(s[m],7-(n&7))&1)>>>0
q.a=n+1}return p},
$S:9}
A.eg.prototype={}
A.db.prototype={}
A.dU.prototype={
B(){var s=0,r=A.G(t.a),q,p=this,o,n,m,l,k
var $async$B=A.H(function(a,b){if(a===1)return A.D(b,r)
for(;;)switch(s){case 0:if(p.r)A.n(B.F)
o=p.f
n=p.b
if(o>=n.length){q=null
s=1
break}m=n[o]
n=p.c
if(!(o<n.length)){q=A.a(n,o)
s=1
break}l=B.b.F(n[o]*1e6,48e3)
n=p.d
if(!(o<n.length)){q=A.a(n,o)
s=1
break}k=B.b.F(n[o]*1e6,48e3)
p.f=o+1
q=new A.ai(m,l,l,k,!0,0)
s=1
break
case 1:return A.E(q,r)}})
return A.F($async$B,r)},
A(a){var s=0,r=A.G(t.H),q,p=this,o,n,m,l,k,j
var $async$A=A.H(function(b,c){if(b===1)return A.D(c,r)
for(;;)A:switch(s){case 0:if(p.r)A.n(B.F)
o=p.c
n=o.length
m=n-1
for(l=0,k=0;l<=m;){j=B.b.H(l+m,1)
if(!(j<n)){q=A.a(o,j)
s=1
break A}if(B.b.F(o[j]*1e6,48e3)<=a){l=j+1
k=j}else m=j-1}p.f=n===0?0:k
case 1:return A.E(q,r)}})
return A.F($async$A,r)},
gU(){return this.b.length===0?null:B.b.F(this.e*1e6,48e3)},
ga_(){return!0},
u(){var s=0,r=A.G(t.H),q,p=this
var $async$u=A.H(function(a,b){if(a===1)return A.D(b,r)
for(;;)switch(s){case 0:q=p.r=!0
s=1
break
case 1:return A.E(q,r)}})
return A.F($async$u,r)},
ga1(){return this.a}}
A.aZ.prototype={
L(){return"_Src."+this.b}}
A.e7.prototype={
B(){var s=0,r=A.G(t.a),q,p=this,o,n,m,l,k,j,i,h,g
var $async$B=A.H(function(a,b){if(a===1)return A.D(b,r)
for(;;)switch(s){case 0:if(p.x)A.n(B.E)
o=p.w
n=p.c
if(o>=n){q=null
s=1
break}m=p.f
l=p.e
k=4096*(A.bu(m)*l)
j=n-o
if(j>k)j=k
j-=B.b.aL(j,A.bu(m)*l)
if(j<=0){q=null
s=1
break}i=p.bO(p.b+o,j)
h=B.b.t(j,A.bu(m)*l)
o=p.w
n=p.d
g=B.b.t(B.b.t(o,A.bu(m)*l)*1e6,n)
p.w=o+j
q=new A.ai(i,g,g,B.b.t(h*1e6,n),!0,0)
s=1
break
case 1:return A.E(q,r)}})
return A.F($async$B,r)},
bO(a,b){var s,r,q,p,o,n,m,l,k,j,i=this.a,h=J.cw(B.j.gI(i),i.byteOffset+a,b)
switch(this.f.a){case 1:case 3:return new Uint8Array(A.K(h))
case 0:s=new Uint8Array(b*2)
r=A.a2(s,0,null)
for(i=h.length,q=r.$flags|0,p=0;p<b;++p){if(!(p<i))return A.a(h,p)
o=h[p]
q&2&&A.z(r,7)
r.setInt16(p*2,o-128<<8>>>0,!0)}return s
case 2:n=B.b.F(b,3)
s=new Uint8Array(n*4)
r=A.a2(s,0,null)
for(i=r.$flags|0,q=h.length,p=0;p<n;++p){o=p*3
if(!(o<q))return A.a(h,o)
m=h[o]
l=o+1
if(!(l<q))return A.a(h,l)
k=h[l]
o+=2
if(!(o<q))return A.a(h,o)
j=(m|k<<8|h[o]<<16)>>>0
if((j&8388608)!==0)j-=16777216
i&2&&A.z(r,12)
r.setFloat32(p*4,j/8388608,!0)}return s}},
A(a){var s=0,r=A.G(t.H),q=this,p,o,n
var $async$A=A.H(function(b,c){if(b===1)return A.D(c,r)
for(;;)switch(s){case 0:if(q.x)A.n(B.E)
p=q.f
o=q.e
n=B.b.c9(B.b.F(a*q.d,1e6)*(A.bu(p)*o),0,q.c)
q.w=n-B.b.aL(n,A.bu(p)*o)
return A.E(null,r)}})
return A.F($async$A,r)},
gU(){var s=this,r=s.d
return r>0?B.b.t(B.b.t(s.c,A.bu(s.f)*s.e)*1e6,r):null},
ga_(){return!0},
u(){var s=0,r=A.G(t.H),q,p=this
var $async$u=A.H(function(a,b){if(a===1)return A.D(b,r)
for(;;)switch(s){case 0:q=p.x=!0
s=1
break
case 1:return A.E(q,r)}})
return A.F($async$u,r)},
ga1(){return this.r}}
A.f0.prototype={
$1(a){var s=0,r=A.G(t.cp),q,p=this,o,n,m,l,k,j,i
var $async$$1=A.H(function(b,c){if(b===1)return A.D(c,r)
for(;;)switch(s){case 0:if("open"===a){o=p.b
n=A.eP(o.m(0,"container"))
o=o.m(0,"bytes")
o.toString
t.p.a(o)
m=A.ir(o,n==null?null:A.cI(B.aL,n,t.e))
if(m==null)throw A.b(B.ag)
p.a.a=m
o=m.ga1()
l=m.gU()
m.ga_()
q=new A.aR(o,l,!0)
s=1
break}s="read"===a?3:4
break
case 3:s=5
return A.cp(p.a.a.B(),$async$$1)
case 5:k=c
q=k==null?null:new A.aP(k)
s=1
break
case 4:j=null
o=!1
if(t.j.b(a)){l=J.ct(a)
if(l.gk(a)===2)if("seek"===l.m(a,0)){i=l.m(a,1)
o=A.cq(i)
if(o){A.aa(i)
j=i}}}s=o?6:7
break
case 6:s=8
return A.cp(p.a.a.A(j),$async$$1)
case 8:q=null
s=1
break
case 7:throw A.b(A.af("unknown op: "+A.p(a)))
case 1:return A.E(q,r)}})
return A.F($async$$1,r)},
$S:19}
A.W.prototype={
L(){return"VideoCodec."+this.b}}
A.Z.prototype={
L(){return"AudioCodec."+this.b}}
A.I.prototype={
L(){return"Container."+this.b}}
A.ak.prototype={}
A.aA.prototype={}
A.ad.prototype={}
A.aR.prototype={
gbv(){return 3329},
bi(){var s,r,q,p,o,n=A.hw(),m=this.b,l=m==null,k=l?0:1,j=n.a
j.D(k)
if(!l)n.Y(m)
j.D(this.c?1:0)
l=this.a
n.bx(l.length)
for(k=l.length,s=n.b,r=0;r<l.length;l.length===k||(0,A.b5)(l),++r){q=l[r]
if(q instanceof A.aA){j.D(0)
p=B.e.J(q.a.b)
o=n.gac()
o.$flags&2&&A.z(o,10)
o.setUint16(0,p.length,!0)
j.j(0,new Uint8Array(A.K(new Uint8Array(s.subarray(0,A.aD(0,2,8))))))
j.j(0,p)
o.setUint32(0,q.b,!0)
j.j(0,new Uint8Array(A.K(new Uint8Array(s.subarray(0,A.aD(0,4,8))))))
o.setUint32(0,q.c,!0)
j.j(0,new Uint8Array(A.K(new Uint8Array(s.subarray(0,A.aD(0,4,8))))))
o.setUint32(0,q.d,!0)
j.j(0,new Uint8Array(A.K(new Uint8Array(s.subarray(0,A.aD(0,4,8))))))
o.setUint32(0,q.e,!0)
j.j(0,new Uint8Array(A.K(new Uint8Array(s.subarray(0,A.aD(0,4,8))))))
n.Y(q.r)
n.bk(q.f)
continue}if(q instanceof A.ad){j.D(1)
p=B.e.J(q.a.b)
o=n.gac()
o.$flags&2&&A.z(o,10)
o.setUint16(0,p.length,!0)
j.j(0,new Uint8Array(A.K(new Uint8Array(s.subarray(0,A.aD(0,2,8))))))
j.j(0,p)
o.setUint32(0,q.b,!0)
j.j(0,new Uint8Array(A.K(new Uint8Array(s.subarray(0,A.aD(0,4,8))))))
o.setUint32(0,q.c,!0)
j.j(0,new Uint8Array(A.K(new Uint8Array(s.subarray(0,A.aD(0,4,8))))))
n.bk(q.d)}}return j.aJ()},
$iaT:1}
A.aP.prototype={
gbv(){return 3330},
bi(){var s,r,q=A.hw(),p=this.a
q.Y(p.b)
q.Y(p.c)
q.Y(p.d)
s=p.e?1:0
r=q.a
r.D(s)
q.ag(p.f)
q.bg(p.a)
return r.aJ()},
$iaT:1}
A.eO.prototype={
gac(){var s,r=this,q=r.c
if(q===$){s=A.a2(r.b,0,null)
r.c!==$&&A.kT()
r.c=s
q=s}return q},
bx(a){var s=this.gac()
s.$flags&2&&A.z(s,10)
s.setUint16(0,a,!0)
this.a.j(0,new Uint8Array(A.K(B.d.a2(this.b,0,2))))},
ag(a){var s=this.gac()
s.$flags&2&&A.z(s,11)
s.setUint32(0,a,!0)
this.a.j(0,new Uint8Array(A.K(B.d.a2(this.b,0,4))))},
Y(a){var s,r=a<0,q=r?-a:a,p=B.b.F(q,4294967296)
this.ag(q-p*4294967296)
this.ag(p)
s=r?1:0
this.a.D(s)},
aM(a){var s=B.e.J(a)
this.bx(s.length)
this.a.j(0,s)},
bg(a){this.ag(a.length)
this.a.j(0,a)},
bk(a){var s,r,q=this
if(a==null){q.a.D(0)
return}s=a.a
r=q.a
r.D(1)
if(s!=null){r.D(0)
q.aM(s.b)}else{r.D(1)
q.aM(a.b.b)}q.bg(a.c)}}
A.dg.prototype={
S(a){var s=this.c,r=this.a.byteLength
if(s+a>r)throw A.b(A.a3("demux protocol: truncated message (wanted "+a+" bytes at "+s+" of "+r+")",null,null))},
O(){this.S(1)
return this.b.getUint8(this.c++)},
bw(){var s,r=this
r.S(2)
s=r.b.getUint16(r.c,!0)
r.c+=2
return s},
af(){var s,r=this
r.S(4)
s=r.b.getUint32(r.c,!0)
r.c+=4
return s},
X(){var s=this.af(),r=this.af()*4294967296+s
return this.O()===1?-r:r},
al(){var s,r,q=this,p=q.bw()
q.S(p)
s=q.c
s=t.L.a(A.d0(q.a,s,s+p))
r=B.b1.J(s)
q.c+=p
return r},
bf(){var s,r,q=this,p=q.af()
q.S(p)
s=q.c
r=new Uint8Array(A.K(A.d0(q.a,s,s+p)))
q.c+=p
return r},
bj(){var s,r,q,p=this
if(p.O()===0)return null
s=p.O()
r=p.al()
q=p.bf()
return s===0?new A.ah(A.cI(B.P,r,t.G),null,q):new A.ah(null,A.cI(B.Q,r,t.q),q)}}
A.dN.prototype={
i(a){return A.fH(this).i(0)+": "+this.a}}
A.w.prototype={
i(a){return"CodecInitException["+this.b+"]: "+this.a}}
A.aG.prototype={
i(a){return"CodecRuntimeException["+this.b+"]: "+this.a}}
A.ai.prototype={
i(a){var s=this,r=s.e?"KEY":"P/B"
return"EncodedPacket("+s.a.length+"B, pts="+s.b+"us, dts="+s.c+"us, "+r+", track="+s.f+")"}}
A.ah.prototype={}
A.fb.prototype={
$1(a){var s,r,q,p,o,n=A.jx(A.b_(a).data)
if(n==null)return
r=this.a
q=r.a
if(q!=null){q.cd(n)
return}s=null
try{s=A.fF(n.b,n.d)}catch(p){s=null}o=new A.dl(A.hb(t.B),new A.bl(new A.j($.i,t.D),t.h))
r.a=o
A.dw(o,this.b,s,B.aa).cp(new A.fa(),t.H)},
$S:20}
A.fa.prototype={
$1(a){A.b_(v.G.self).close()},
$S:21}
A.dl.prototype={
M(a){var s,r,q={},p=a.d,o=t.p.b(p),n=o?p.byteLength:0,m=new Uint8Array(12),l=A.a2(m,0,null)
l.$flags&2&&A.z(l,9)
l.setUint8(0,1)
l.setUint8(1,a.a.c)
l.setUint16(2,a.b,!0)
l.setUint32(4,a.c,!0)
l.setUint32(8,n,!0)
q.h=m
s=A.f([],t.f)
if(p!=null){p=o?p:A.fC(p,s)
q.p=p}r=A.kh(null,s)
A.b_(v.G.self).postMessage(q,r)},
cd(a){var s=this.a,r=s.b
if((r&4)!==0)return
s.j(0,a)},
$iiX:1}
A.eZ.prototype={
$1(a){var s,r,q
for(s=this.a,r=s.length,q=0;q<r;++q)if(s[q]===a)return
B.a.j(s,a)
this.b[s.length-1]=a},
$S:22}
A.eY.prototype={
$2(a,b){this.a[A.p(a)]=A.fC(b,this.b)},
$S:1}
A.cV.prototype={
L(){return"SpawnHost."+this.b}}
A.cW.prototype={
L(){return"SpawnPayload."+this.b}}
A.dW.prototype={
bu(){return A.h_(["hosted","dart","payload","js","zeroCopyTransfer",!0],t.N,t.X)},
i(a){return"SpawnCaps(hosted: dart, payload: js, zeroCopyTransfer: true)"}}
A.cn.prototype={
ci(a){var s,r,q
t.k.a(a)
this.e=a
s=this.d
if(s.length===0)return
r=A.fl(s,t.B)
B.a.N(s)
for(s=r.length,q=0;q<r.length;r.length===s||(0,A.b5)(r),++q)this.aQ(r[q],a)},
bW(a){var s,r,q=this
t.B.a(a)
switch(a.a.a){case 2:s=q.b
if((s.b&4)===0)s.j(0,A.fF(a.b,a.d))
break
case 3:r=q.e
if(r==null)B.a.j(q.d,a)
else q.aQ(a,r)
break
case 1:q.av()
break
case 0:case 4:case 5:break}},
aQ(a,b){var s,r,q,p,o,n,m,l,k=this,j={}
t.k.a(b)
j.a=null
try{j.a=A.fF(a.b,a.d)}catch(n){s=A.R(n)
r=A.Y(n)
k.aa(a.c,s,r)
return}q=A.j2()
try{m=q
j=A.iv(new A.eL(j,b),t.X)
l=m.b
if(l==null?m!=null:l!==m)A.n(new A.ba("Local '' has already been initialized."))
m.b=j}catch(n){p=A.R(n)
o=A.Y(n)
k.aa(a.c,p,o)
return}j=q
m=j.b
if(m==null?j==null:m===j)A.n(new A.ba("Local '' has not been initialized."))
m.ae(new A.eM(k,a),new A.eN(k,a),t.P)},
aa(a,b,c){var s,r,q
t.l.a(c)
s=J.as(b)
r=A.L(s.gl(b).a,null)
s=s.i(b)
q=c.i(0)
this.a.M(new A.S(B.k,0,a,B.e.J(r+"\n"+A.fM(s,"\n"," ")+"\n"+q)))},
bY(){return this.av()},
av(){var s,r=this
if(r.f)return
r.f=!0
s=r.c
if((s.a.a&30)===0)s.ca()
r.bR()
s=r.b
if((s.b&4)===0)s.u()},
bR(){var s,r,q,p,o,n,m,l=this.d
if(l.length===0)return
s=A.fl(l,t.B)
B.a.N(l)
for(l=s.length,r=this.a,q=0;q<s.length;s.length===l||(0,A.b5)(s),++q){p=s[q]
o=new A.az("spawn: the worker closed without installing a request handler (WorkerChannel.handleRequests was never called)")
n=A.L(o.gl(0).a,null)
o=o.i(0)
m=B.B.i(0)
r.M(new A.S(B.k,0,p.c,B.e.J(n+"\n"+A.fM(o,"\n"," ")+"\n"+m)))}},
$ifo:1}
A.eL.prototype={
$0(){return this.b.$1(this.a.a)},
$S:24}
A.eM.prototype={
$1(a){var s,r,q,p,o,n,m=this
try{s=null
r=null
q=A.kx(a)
s=q.a
r=q.b
m.a.a.M(new A.S(B.V,s,m.b.c,r))}catch(n){p=A.R(n)
o=A.Y(n)
m.a.aa(m.b.c,p,o)}},
$S:25}
A.eN.prototype={
$2(a,b){this.a.aa(this.b.c,A.ab(a),t.l.a(b))},
$S:7}
A.S.prototype={
i(a){var s=this,r=s.a.i(0),q=s.d
return"Frame("+r+", typeId: "+s.b+", correlationId: "+s.c+", payload: "+A.p(t.p.b(q)?""+q.byteLength+" bytes":J.bA(q))+")"}}
A.eT.prototype={
$2(a,b){if(typeof a!="string")throw A.b(A.au(a,this.a,"spawn map keys must be String, got "+J.bA(a).i(0)))
A.fv(b,this.b,this.a+'["'+a+'"]')},
$S:1}
A.bU.prototype={
i(a){return"PlatformValue("+J.bA(this.a).i(0)+")"}}
A.ag.prototype={
L(){return"WireKind."+this.b}}
A.d3.prototype={
i(a){var s=this
return"WireHeader(v"+s.a+", "+s.b.i(0)+", typeId: "+s.c+", correlationId: "+s.d+", payloadLength: "+s.e+")"},
K(a,b){var s=this
if(b==null)return!1
return b instanceof A.d3&&b.a===s.a&&b.b===s.b&&b.c===s.c&&b.d===s.d&&b.e===s.e},
gp(a){var s=this
return A.h3(s.a,s.b,s.c,s.d,s.e)}}
A.e8.prototype={
bq(a,b){var s,r
t.w.a(b)
if(a<1||a>65535)throw A.b(A.au(a,"typeId","must be in 1..65535 (0 is reserved)"))
s=this.a
r=s.m(0,a)
if(r!=null&&!J.cv(r,b))throw A.b(A.af("spawn: typeId "+a+" is already registered to a different decoder"))
s.q(0,a,b)}};(function aliases(){var s=J.aw.prototype
s.bE=s.i
s=A.h.prototype
s.bF=s.bB})();(function installTearOffs(){var s=hunkHelpers._static_1,r=hunkHelpers._static_0,q=hunkHelpers._static_2,p=hunkHelpers._instance_2u,o=hunkHelpers._instance_1u,n=hunkHelpers._instance_0u
s(A,"kl","iZ",2)
s(A,"km","j_",2)
s(A,"kn","j0",2)
r(A,"hS","ke",0)
q(A,"ko","jX",6)
p(A.j.prototype,"gbJ","bK",6)
s(A,"kq","jy",3)
s(A,"kv","du",26)
s(A,"ku","iU",27)
s(A,"kt","iL",28)
var m
o(m=A.cn.prototype,"gbV","bW",23)
n(m,"gbX","bY",0)})();(function inheritance(){var s=hunkHelpers.mixin,r=hunkHelpers.inherit,q=hunkHelpers.inheritMany
r(A.d,null)
q(A.d,[A.fj,J.cL,A.bZ,J.bB,A.d9,A.d7,A.q,A.h,A.av,A.dV,A.e,A.aL,A.bG,A.N,A.aS,A.aY,A.e_,A.dT,A.bH,A.ce,A.Q,A.dK,A.bO,A.ef,A.dk,A.a5,A.de,A.eE,A.eC,A.c4,A.A,A.M,A.c6,A.ao,A.j,A.d4,A.c0,A.cf,A.d5,A.c5,A.aB,A.da,A.a8,A.di,A.co,A.bj,A.df,A.c8,A.cF,A.cH,A.eu,A.eJ,A.eG,A.dc,A.c_,A.eh,A.bI,A.u,A.dj,A.aQ,A.e9,A.dy,A.ew,A.bQ,A.dO,A.d6,A.ap,A.dP,A.d8,A.eg,A.db,A.dU,A.e7,A.ak,A.aR,A.aP,A.eO,A.dg,A.dN,A.ai,A.ah,A.dl,A.dW,A.cn,A.S,A.bU,A.d3,A.e8])
q(J.cL,[J.cN,J.bK,J.bM,J.b8,J.b9,J.bL,J.b7])
q(J.bM,[J.aw,J.o,A.ax,A.bS])
q(J.aw,[J.cS,J.c2,J.aj])
r(J.cM,A.bZ)
r(J.dI,J.o)
q(J.bL,[J.bJ,J.cO])
q(A.q,[A.ba,A.al,A.cP,A.d2,A.cU,A.dd,A.bN,A.cA,A.a1,A.c3,A.d1,A.az,A.cG])
r(A.bk,A.h)
r(A.cE,A.bk)
q(A.av,[A.cC,A.cD,A.d_,A.f4,A.f6,A.eb,A.ea,A.eR,A.eq,A.dX,A.dQ,A.dS,A.eQ,A.f0,A.fb,A.fa,A.eZ,A.eM])
q(A.cC,[A.f9,A.ec,A.ed,A.eD,A.ei,A.em,A.el,A.ek,A.ej,A.ep,A.eo,A.en,A.dY,A.eB,A.eA,A.ee,A.ex,A.ez,A.eX,A.eI,A.eH,A.eL])
q(A.e,[A.bE,A.br])
q(A.bE,[A.aK,A.bF,A.bP])
r(A.c1,A.aK)
r(A.bp,A.aY)
r(A.bq,A.bp)
r(A.bT,A.al)
q(A.d_,[A.cX,A.b6])
r(A.aJ,A.Q)
q(A.cD,[A.f5,A.eS,A.f_,A.er,A.dM,A.ev,A.dR,A.eY,A.eN,A.eT])
r(A.bb,A.ax)
q(A.bS,[A.aN,A.C])
q(A.C,[A.c9,A.cb])
r(A.ca,A.c9)
r(A.bR,A.ca)
r(A.cc,A.cb)
r(A.U,A.cc)
q(A.bR,[A.bc,A.bd])
q(A.U,[A.be,A.bf,A.bg,A.bh,A.bi,A.aO,A.ay])
r(A.ci,A.dd)
r(A.bl,A.c6)
r(A.bm,A.cf)
r(A.ch,A.c0)
r(A.bn,A.ch)
r(A.bo,A.c5)
r(A.aU,A.aB)
r(A.dh,A.co)
r(A.cd,A.bj)
r(A.c7,A.cd)
r(A.cR,A.bN)
r(A.cQ,A.cF)
q(A.cH,[A.dJ,A.e6,A.e5])
r(A.et,A.eu)
q(A.a1,[A.bW,A.cK])
q(A.dc,[A.aZ,A.W,A.Z,A.I,A.cV,A.cW,A.ag])
q(A.ak,[A.aA,A.ad])
q(A.dN,[A.w,A.aG])
s(A.bk,A.aS)
s(A.c9,A.h)
s(A.ca,A.N)
s(A.cb,A.h)
s(A.cc,A.N)
s(A.bm,A.d5)})()
var v={G:typeof self!="undefined"?self:globalThis,typeUniverse:{eC:new Map(),tR:{},eT:{},tPV:{},sEA:[]},mangledGlobalNames:{c:"int",m:"double",b4:"num",a7:"String",b2:"bool",u:"Null",k:"List",d:"Object",dL:"Map",r:"JSObject"},mangledNames:{},types:["~()","~(d?,d?)","~(~())","@(@)","u(@)","u()","~(d,a6)","u(d,a6)","@()","c(c)","O<~>()","@(@,a7)","@(a7)","u(~())","~(@)","u(@,a6)","~(c,@)","c(ap,ap)","b2(ak)","O<aT?>(d?)","u(r)","u(~)","~(d)","~(S)","d?()","u(d?)","O<~>(fo)","aR(an)","aP(an)"],interceptorsByTag:null,leafTags:null,arrayRti:Symbol("$ti"),rttc:{"2;":(a,b)=>c=>c instanceof A.bq&&a.b(c.a)&&b.b(c.b)}}
A.ji(v.typeUniverse,JSON.parse('{"aj":"aw","cS":"aw","c2":"aw","kX":"ax","o":{"k":["1"],"r":[],"e":["1"]},"cN":{"b2":[],"l":[]},"bK":{"u":[],"l":[]},"bM":{"r":[]},"aw":{"r":[]},"cM":{"bZ":[]},"dI":{"o":["1"],"k":["1"],"r":[],"e":["1"]},"bB":{"ae":["1"]},"bL":{"m":[],"b4":[]},"bJ":{"m":[],"c":[],"b4":[],"l":[]},"cO":{"m":[],"b4":[],"l":[]},"b7":{"a7":[],"h4":[],"l":[]},"d9":{"fg":[]},"d7":{"fg":[]},"ba":{"q":[]},"cE":{"h":["c"],"aS":["c"],"k":["c"],"e":["c"],"h.E":"c","aS.E":"c"},"bE":{"e":["1"]},"aK":{"e":["1"]},"c1":{"aK":["1"],"e":["1"],"aK.E":"1"},"aL":{"ae":["1"]},"bF":{"e":["1"]},"bG":{"ae":["1"]},"bk":{"h":["1"],"aS":["1"],"k":["1"],"e":["1"]},"bq":{"bp":[],"aY":[]},"bT":{"al":[],"q":[]},"cP":{"q":[]},"d2":{"q":[]},"ce":{"a6":[]},"av":{"aI":[]},"cC":{"aI":[]},"cD":{"aI":[]},"d_":{"aI":[]},"cX":{"aI":[]},"b6":{"aI":[]},"cU":{"q":[]},"aJ":{"Q":["1","2"],"fY":["1","2"],"dL":["1","2"],"Q.K":"1","Q.V":"2"},"bP":{"e":["1"]},"bO":{"ae":["1"]},"bp":{"aY":[]},"ay":{"U":[],"an":[],"h":["c"],"C":["c"],"k":["c"],"T":["c"],"r":[],"t":[],"e":["c"],"N":["c"],"l":[],"h.E":"c"},"ax":{"r":[],"bC":[],"l":[]},"bb":{"ax":[],"r":[],"bC":[],"l":[]},"bS":{"r":[],"t":[]},"dk":{"bC":[]},"aN":{"dA":[],"r":[],"t":[],"l":[]},"C":{"T":["1"],"r":[],"t":[]},"bR":{"h":["m"],"C":["m"],"k":["m"],"T":["m"],"r":[],"t":[],"e":["m"],"N":["m"]},"U":{"h":["c"],"C":["c"],"k":["c"],"T":["c"],"r":[],"t":[],"e":["c"],"N":["c"]},"bc":{"dD":[],"h":["m"],"C":["m"],"k":["m"],"T":["m"],"r":[],"t":[],"e":["m"],"N":["m"],"l":[],"h.E":"m"},"bd":{"dE":[],"h":["m"],"C":["m"],"k":["m"],"T":["m"],"r":[],"t":[],"e":["m"],"N":["m"],"l":[],"h.E":"m"},"be":{"U":[],"dF":[],"h":["c"],"C":["c"],"k":["c"],"T":["c"],"r":[],"t":[],"e":["c"],"N":["c"],"l":[],"h.E":"c"},"bf":{"U":[],"dG":[],"h":["c"],"C":["c"],"k":["c"],"T":["c"],"r":[],"t":[],"e":["c"],"N":["c"],"l":[],"h.E":"c"},"bg":{"U":[],"dH":[],"h":["c"],"C":["c"],"k":["c"],"T":["c"],"r":[],"t":[],"e":["c"],"N":["c"],"l":[],"h.E":"c"},"bh":{"U":[],"e1":[],"h":["c"],"C":["c"],"k":["c"],"T":["c"],"r":[],"t":[],"e":["c"],"N":["c"],"l":[],"h.E":"c"},"bi":{"U":[],"e2":[],"h":["c"],"C":["c"],"k":["c"],"T":["c"],"r":[],"t":[],"e":["c"],"N":["c"],"l":[],"h.E":"c"},"aO":{"U":[],"e3":[],"h":["c"],"C":["c"],"k":["c"],"T":["c"],"r":[],"t":[],"e":["c"],"N":["c"],"l":[],"h.E":"c"},"dd":{"q":[]},"ci":{"al":[],"q":[]},"c4":{"dC":["1"]},"A":{"ae":["1"]},"br":{"e":["1"]},"M":{"q":[]},"c6":{"dC":["1"]},"bl":{"c6":["1"],"dC":["1"]},"j":{"O":["1"]},"cf":{"ha":["1"],"hn":["1"],"aV":["1"]},"bm":{"d5":["1"],"cf":["1"],"ha":["1"],"hn":["1"],"aV":["1"]},"bn":{"ch":["1"],"c0":["1"]},"bo":{"c5":["1"],"cY":["1"],"aV":["1"]},"c5":{"cY":["1"],"aV":["1"]},"ch":{"c0":["1"]},"aU":{"aB":["1"]},"da":{"aB":["@"]},"co":{"hf":[]},"dh":{"co":[],"hf":[]},"c7":{"bj":["1"],"e":["1"]},"c8":{"ae":["1"]},"h":{"k":["1"],"e":["1"]},"Q":{"dL":["1","2"]},"bj":{"e":["1"]},"cd":{"bj":["1"],"e":["1"]},"bN":{"q":[]},"cR":{"q":[]},"cQ":{"cF":["d?","a7"]},"m":{"b4":[]},"c":{"b4":[]},"k":{"e":["1"]},"a7":{"h4":[]},"dc":{"aH":[]},"cA":{"q":[]},"al":{"q":[]},"a1":{"q":[]},"bW":{"q":[]},"cK":{"q":[]},"c3":{"q":[]},"d1":{"q":[]},"az":{"q":[]},"cG":{"q":[]},"c_":{"q":[]},"dj":{"a6":[]},"aQ":{"iS":[]},"aZ":{"aH":[]},"W":{"aH":[]},"Z":{"aH":[]},"I":{"aH":[]},"aA":{"ak":[]},"ad":{"ak":[]},"aR":{"aT":[]},"aP":{"aT":[]},"dl":{"iX":[]},"cV":{"aH":[]},"cW":{"aH":[]},"cn":{"fo":[]},"ag":{"aH":[]},"dA":{"t":[]},"dH":{"k":["c"],"t":[],"e":["c"]},"an":{"k":["c"],"t":[],"e":["c"]},"e3":{"k":["c"],"t":[],"e":["c"]},"dF":{"k":["c"],"t":[],"e":["c"]},"e1":{"k":["c"],"t":[],"e":["c"]},"dG":{"k":["c"],"t":[],"e":["c"]},"e2":{"k":["c"],"t":[],"e":["c"]},"dD":{"k":["m"],"t":[],"e":["m"]},"dE":{"k":["m"],"t":[],"e":["m"]}}'))
A.jh(v.typeUniverse,JSON.parse('{"bE":1,"bk":1,"C":1,"aB":1,"cd":1,"cH":2}'))
var u={c:"Error handler must accept one Object or one Object and a StackTrace as arguments, and return a value of the returned future's type"}
var t=(function rtii(){var s=A.aE
return{V:s("@<~>"),n:s("M"),q:s("Z"),x:s("bC"),W:s("dA"),e:s("I"),C:s("q"),h4:s("dD"),gN:s("dE"),B:s("S"),Z:s("aI"),dQ:s("dF"),an:s("dG"),U:s("dH"),hf:s("e<@>"),hb:s("e<c>"),b4:s("o<S>"),f:s("o<d>"),s:s("o<a7>"),J:s("o<ak>"),r:s("o<an>"),fx:s("o<ap>"),gn:s("o<@>"),t:s("o<c>"),c:s("o<d?>"),T:s("bK"),m:s("r"),g:s("aj"),aU:s("T<@>"),j:s("k<@>"),L:s("k<c>"),eE:s("dL<a7,d?>"),u:s("bb"),A:s("aN"),E:s("bc"),c2:s("bd"),at:s("be"),ha:s("bf"),cv:s("bg"),eB:s("U"),d:s("bh"),dk:s("bi"),gi:s("aO"),Y:s("ay"),P:s("u"),K:s("d"),gT:s("kY"),bQ:s("+()"),l:s("a6"),N:s("a7"),ff:s("ak"),dm:s("l"),eK:s("al"),ak:s("t"),h7:s("e1"),bv:s("e2"),go:s("e3"),p:s("an"),bI:s("c2"),G:s("W"),bG:s("aT"),w:s("aT(an)"),h:s("bl<~>"),_:s("j<@>"),fJ:s("j<c>"),D:s("j<~>"),bf:s("ap"),fv:s("cg<d?>"),g6:s("br<d6>"),y:s("b2"),al:s("b2(d)"),i:s("m"),z:s("@"),O:s("@()"),v:s("@(d)"),Q:s("@(d,a6)"),S:s("c"),a:s("ai?"),eH:s("O<u>?"),bX:s("r?"),dE:s("ay?"),X:s("d?"),k:s("d?(d?)"),c8:s("a7?"),cp:s("aT?"),ev:s("aB<@>?"),F:s("ao<@,@>?"),R:s("df?"),fQ:s("b2?"),I:s("m?"),h6:s("c?"),cg:s("b4?"),b:s("~()?"),o:s("b4"),H:s("~"),M:s("~()"),d5:s("~(d)"),da:s("~(d,a6)")}})();(function constants(){var s=hunkHelpers.makeConstList
B.aB=J.cL.prototype
B.a=J.o.prototype
B.b=J.bJ.prototype
B.I=J.bL.prototype
B.m=J.b7.prototype
B.aC=J.aj.prototype
B.aD=J.bM.prototype
B.j=A.aN.prototype
B.d=A.ay.prototype
B.R=J.cS.prototype
B.r=J.c2.prototype
B.f=new A.Z(0,"aac")
B.h=new A.Z(1,"opus")
B.v=new A.Z(3,"mp3")
B.w=new A.Z(5,"pcmS16le")
B.x=new A.Z(6,"pcmF32le")
B.a2=new A.bG(A.aE("bG<0&>"))
B.y=function getTagFallback(o) {
  var s = Object.prototype.toString.call(o);
  return s.substring(8, s.length - 1);
}
B.a3=function() {
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
B.a8=function(getTagFallback) {
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
B.a4=function(hooks) {
  if (typeof dartExperimentalFixupGetTag != "function") return hooks;
  hooks.getTag = dartExperimentalFixupGetTag(hooks.getTag);
}
B.a7=function(hooks) {
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
B.a6=function(hooks) {
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
B.a5=function(hooks) {
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
B.z=function(hooks) { return hooks; }

B.a9=new A.cQ()
B.i=new A.dV()
B.b9=new A.cV(0,"dart")
B.ba=new A.cW(1,"js")
B.aa=new A.dW()
B.e=new A.e6()
B.A=new A.da()
B.c=new A.dh()
B.B=new A.dj()
B.ab=new A.w("ogg","first packet is not OpusHead")
B.ac=new A.w("wav","EXTENSIBLE SubFormat is not a PCM/IEEE-float GUID")
B.ad=new A.w("ogg","not an Ogg stream")
B.ae=new A.w("mp4","no stbl samples (fragmented MP4?) \u2014 deferring to fallback")
B.af=new A.w("adts","bad ADTS sample-rate/channels")
B.ag=new A.w("container-worker","no pure-Dart parser claims this container")
B.ah=new A.w("mp4","no tracks in moov")
B.ai=new A.w("mp3","free-format MP3 (bitrate index 0) is not supported \u2014 its frame length is not derivable from the header")
B.aj=new A.w("mp3","no MPEG Layer III audio frames")
B.ak=new A.w("wav","short WAVE_FORMAT_EXTENSIBLE")
B.al=new A.w("wav","missing data chunk")
B.am=new A.w("adts","no ADTS sync")
B.an=new A.w("ogg","truncated segment table")
B.ao=new A.w("mp4","no moov box")
B.ap=new A.w("wav","missing/short fmt chunk")
B.aq=new A.w("ogg","bad page capture pattern")
B.ar=new A.w("wav","not a RIFF/WAVE file")
B.as=new A.w("ogg","truncated page payload")
B.at=new A.w("mp3","no MPEG Layer III frame sync")
B.C=new A.aG("mp3","demuxer closed")
B.D=new A.aG("mp4","demuxer closed")
B.E=new A.aG("wav","demuxer closed")
B.F=new A.aG("ogg","demuxer closed")
B.G=new A.aG("adts","demuxer closed")
B.n=new A.I(0,"mp4")
B.o=new A.I(10,"adts")
B.p=new A.I(6,"ogg")
B.q=new A.I(7,"wav")
B.H=new A.I(8,"m4a")
B.l=new A.I(9,"mp3")
B.az=new A.bI("demux protocol: unknown track kind",null,null)
B.u=new A.ag(1,1,"bye")
B.aA=new A.S(B.u,0,0,null)
B.aE=new A.dJ(null)
B.t=new A.ag(0,0,"hello")
B.b7=new A.ag(2,2,"message")
B.b8=new A.ag(3,3,"request")
B.V=new A.ag(4,4,"response")
B.k=new A.ag(5,5,"error")
B.aF=s([B.t,B.u,B.b7,B.b8,B.V,B.k],A.aE("o<ag>"))
B.J=s([11025,12e3,8000],t.t)
B.K=s([22050,24e3,16e3],t.t)
B.L=s([44100,48e3,32e3],t.t)
B.aG=s([79,103,103,83],t.t)
B.aH=s([0,8,16,24,32,40,48,56,64,80,96,112,128,144,160,0],t.t)
B.aI=s([480,960,1920,2880,480,960,1920,2880,480,960,1920,2880,480,960,480,960,120,240,480,960,120,240,480,960,120,240,480,960,120,240,480,960],t.t)
B.M=s([79,112,117,115,72,101,97,100],t.t)
B.aJ=s(["Xing","Info"],t.s)
B.aK=s([0,0,0,0,16,0,128,0,0,170,0,56,155,113],t.t)
B.N=s([96e3,88200,64e3,48e3,44100,32e3,24e3,22050,16e3,12e3,11025,8000,7350,0,0,0],t.t)
B.O=s([],t.t)
B.S=new A.W(0,"h264")
B.T=new A.W(1,"hevc")
B.U=new A.W(2,"av1")
B.b2=new A.W(3,"vp9")
B.b3=new A.W(4,"vp8")
B.b4=new A.W(5,"mjpeg")
B.b5=new A.W(6,"prores")
B.b6=new A.W(7,"custom")
B.P=s([B.S,B.T,B.U,B.b2,B.b3,B.b4,B.b5,B.b6],A.aE("o<W>"))
B.au=new A.I(1,"fmp4")
B.av=new A.I(2,"mkv")
B.aw=new A.I(3,"webm")
B.ax=new A.I(4,"mpegts")
B.ay=new A.I(5,"raw")
B.aL=s([B.n,B.au,B.av,B.aw,B.ax,B.ay,B.p,B.q,B.H,B.l,B.o],A.aE("o<I>"))
B.aM=s([0,32,40,48,56,64,80,96,112,128,160,192,224,256,320,0],t.t)
B.aN=s([79,112,117,115,84,97,103,115],t.t)
B.a0=new A.Z(2,"vorbis")
B.a1=new A.Z(4,"flac")
B.Q=s([B.f,B.h,B.a0,B.v,B.a1,B.w,B.x],A.aE("o<Z>"))
B.aO=s([96e3,88200,64e3,48e3,44100,32e3,24e3,22050,16e3,12e3,11025,8000,7350],t.t)
B.aP=A.a0("bC")
B.aQ=A.a0("dA")
B.aR=A.a0("dD")
B.aS=A.a0("dE")
B.aT=A.a0("dF")
B.aU=A.a0("dG")
B.aV=A.a0("dH")
B.aW=A.a0("r")
B.aX=A.a0("d")
B.aY=A.a0("e1")
B.aZ=A.a0("e2")
B.b_=A.a0("e3")
B.b0=A.a0("an")
B.b1=new A.e5(!1)
B.W=new A.db(0,0)
B.X=new A.aZ(0,"u8")
B.Y=new A.aZ(1,"s16")
B.Z=new A.aZ(2,"s24")
B.a_=new A.aZ(3,"f32")})();(function staticFields(){$.es=null
$.X=A.f([],t.f)
$.h6=null
$.fS=null
$.fR=null
$.hT=null
$.hR=null
$.hX=null
$.f2=null
$.f7=null
$.fI=null
$.ey=A.f([],A.aE("o<k<d>?>"))
$.bs=null
$.cr=null
$.cs=null
$.fy=!1
$.i=B.c})();(function lazyInitializers(){var s=hunkHelpers.lazyFinal
s($,"kV","fN",()=>A.kB("_$dart_dartClosure"))
s($,"lb","bz",()=>A.h2(0))
s($,"lj","id",()=>B.c.br(new A.f9(),A.aE("O<~>")))
s($,"lg","ic",()=>A.f([new J.cM()],A.aE("o<bZ>")))
s($,"l_","i_",()=>A.am(A.e0({
toString:function(){return"$receiver$"}})))
s($,"l0","i0",()=>A.am(A.e0({$method$:null,
toString:function(){return"$receiver$"}})))
s($,"l1","i1",()=>A.am(A.e0(null)))
s($,"l2","i2",()=>A.am(function(){var $argumentsExpr$="$arguments$"
try{null.$method$($argumentsExpr$)}catch(r){return r.message}}()))
s($,"l5","i5",()=>A.am(A.e0(void 0)))
s($,"l6","i6",()=>A.am(function(){var $argumentsExpr$="$arguments$"
try{(void 0).$method$($argumentsExpr$)}catch(r){return r.message}}()))
s($,"l4","i4",()=>A.am(A.hd(null)))
s($,"l3","i3",()=>A.am(function(){try{null.$method$}catch(r){return r.message}}()))
s($,"l8","i8",()=>A.am(A.hd(void 0)))
s($,"l7","i7",()=>A.am(function(){try{(void 0).$method$}catch(r){return r.message}}()))
s($,"la","fP",()=>A.iY())
s($,"kW","fc",()=>$.id())
s($,"le","ib",()=>A.h2(4096))
s($,"lc","i9",()=>new A.eI().$0())
s($,"ld","ia",()=>new A.eH().$0())
s($,"lf","dx",()=>A.hV(B.aX))
s($,"l9","fO",()=>new A.e8(A.fZ(t.S,t.w)))})();(function nativeSupport(){!function(){var s=function(a){var m={}
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
hunkHelpers.setOrUpdateInterceptorsByTag({SharedArrayBuffer:A.ax,ArrayBuffer:A.bb,ArrayBufferView:A.bS,DataView:A.aN,Float32Array:A.bc,Float64Array:A.bd,Int16Array:A.be,Int32Array:A.bf,Int8Array:A.bg,Uint16Array:A.bh,Uint32Array:A.bi,Uint8ClampedArray:A.aO,CanvasPixelArray:A.aO,Uint8Array:A.ay})
hunkHelpers.setOrUpdateLeafTags({SharedArrayBuffer:true,ArrayBuffer:true,ArrayBufferView:false,DataView:true,Float32Array:true,Float64Array:true,Int16Array:true,Int32Array:true,Int8Array:true,Uint16Array:true,Uint32Array:true,Uint8ClampedArray:true,CanvasPixelArray:true,Uint8Array:false})
A.C.$nativeSuperclassTag="ArrayBufferView"
A.c9.$nativeSuperclassTag="ArrayBufferView"
A.ca.$nativeSuperclassTag="ArrayBufferView"
A.bR.$nativeSuperclassTag="ArrayBufferView"
A.cb.$nativeSuperclassTag="ArrayBufferView"
A.cc.$nativeSuperclassTag="ArrayBufferView"
A.U.$nativeSuperclassTag="ArrayBufferView"})()
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
var s=A.kJ
if(typeof dartMainRunner==="function"){dartMainRunner(s,[])}else{s([])}})})()
//# sourceMappingURL=demux_worker.dart.js.map
