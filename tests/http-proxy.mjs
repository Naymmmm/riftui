import assert from 'node:assert/strict'
import { EventEmitter } from 'node:events'
import { Readable } from 'node:stream'
import { fetchPublic, validateTarget, publicAddress, proxyMiddleware } from '../scripts/http-proxy.mjs'

for (const ip of ['127.0.0.1','10.0.0.1','192.168.0.1','169.254.169.254','172.16.0.1','100.64.0.1','::1','::ffff:127.0.0.1','fe80::1','fc00::1']) assert.equal(publicAddress(ip), false, ip)
for (const ip of ['1.1.1.1','8.8.8.8','2606:4700:4700::1111']) assert.equal(publicAddress(ip), true, ip)
const resolve = async () => [{ address: '8.8.8.8', family: 4 }]
for (const url of ['file:///etc/passwd', 'http://127.0.0.1/image', 'http://[::1]/image', 'https://user:pass@example.com/a', 'https://example.com:8080/a']) await assert.rejects(validateTarget(url, resolve))
await assert.rejects(validateTarget('https://private.example/a', async () => [{ address:'10.0.0.1',family:4 }]), /private/)
const body = Buffer.from([0x89,0x50,0x4e,0x47,0,255,128,1])
function requestMock(responses) {
  return (url, options, callback) => {
    const req = new EventEmitter()
    req.setTimeout = () => req
    req.destroy = error => req.emit('error', error)
    req.end = () => queueMicrotask(() => {
      options.lookup(url.hostname, { all: true }, (err, addresses) => {
        assert.ifError(err)
        assert.deepEqual(addresses, [{address:'8.8.8.8',family:4}])
      })
      const data = responses.shift()
      const res = Readable.from([data.body || Buffer.alloc(0)])
      res.statusCode = data.status || 200
      res.headers = data.headers || {}
      callback(res)
    })
    return req
  }
}
const result = await fetchPublic('https://image.example/a', { resolve, request: requestMock([{body, headers:{'content-type':'image/png'}}]) })
assert.deepEqual(result.body, body)
await assert.rejects(fetchPublic('https://image.example/a', { resolve, request: requestMock([{status:302, headers:{location:'http://127.0.0.1/secret'}}]) }), /private/)
await assert.rejects(fetchPublic('https://image.example/a', { resolve, limit:2, request: requestMock([{body}]) }), /larger/)
let called = false
const middleware = proxyMiddleware(async () => { called = true; return { status:200, headers:{'content-type':'image/png','set-cookie':'secret'},body } })
function response() { return { headers:{},setHeader(k,v){this.headers[k]=v},end(data){this.body=data} } }
let res = response()
await middleware({url:'/__rift_http?url=https://image.example/a',method:'GET',headers:{}},res,()=>{})
assert(called);assert.deepEqual(res.body,body);assert.equal(res.headers['set-cookie'],undefined);assert.equal(res.headers['X-Rift-Proxy'],'1')
called=false;res=response()
await middleware({url:'/__rift_http?url=https://image.example/a',method:'GET',headers:{origin:'https://other.example',host:'localhost:5199'}},res,()=>{})
assert.equal(res.statusCode,403);assert.equal(called,false)
console.log('Image proxy: binary bytes, pinned DNS, redirects, limits and origins passed')
