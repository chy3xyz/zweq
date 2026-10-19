import type { CustomRequestOptions, HttpError, IResponse } from '@/http/types'
import { useFanStore } from '@/store/fan'
import { toLoginPage } from '@/utils/toLoginPage'
import { createHttpError, getResponseMessage, HttpErrorType, isSuccessResultCode, ResultEnum, ShowMessage } from './tools/enum'

/**
 * 统一请求封装（ZWEQ C 端）。
 * - 响应契约 { code, msg/message, data }，直接 resolve data
 * - 401 / 业务码 401：清空粉丝登录态并跳转登录页
 * - 业务/HTTP/网络错误默认 toast，可用 hideErrorToast 关闭
 */
export function http<T>(options: CustomRequestOptions) {
  return new Promise<T>((resolve, reject) => {
    uni.request({
      ...options,
      dataType: 'json',
      // #ifndef MP-WEIXIN
      responseType: 'json',
      // #endif
      success: (res) => {
        const responseData = res.data as Partial<IResponse<T>>
        const code = responseData?.code

        // 401：HTTP 状态码或业务码
        const isTokenExpired = res.statusCode === 401 || code === ResultEnum.Unauthorized
        if (isTokenExpired) {
          const fanStore = useFanStore()
          fanStore.clear()
          toLoginPage({ mode: 'reLaunch' })
          return reject(createHttpError({
            type: HttpErrorType.Auth,
            code,
            statusCode: res.statusCode,
            message: getResponseMessage(responseData, '登录已过期，请重新登录'),
            data: responseData?.data,
            raw: res,
          }))
        }

        // 2xx：检查业务码
        if (res.statusCode >= 200 && res.statusCode < 300) {
          if (!isSuccessResultCode(code as number)) {
            const httpError = createHttpError({
              type: HttpErrorType.Business,
              code,
              statusCode: res.statusCode,
              message: getResponseMessage(responseData),
              data: responseData?.data,
              raw: responseData,
            })
            if (!options.hideErrorToast) {
              uni.showToast({ icon: 'none', title: httpError.message })
            }
            return reject(httpError)
          }
          return resolve(responseData.data as T)
        }

        // 其他 HTTP 错误
        const httpError = createHttpError({
          type: HttpErrorType.Http,
          code,
          statusCode: res.statusCode,
          message: getResponseMessage(responseData, ShowMessage(res.statusCode)),
          data: responseData?.data,
          raw: res,
        })
        if (!options.hideErrorToast) {
          uni.showToast({ icon: 'none', title: httpError.message })
        }
        reject(httpError)
      },
      fail(err) {
        const httpError = createHttpError({
          type: HttpErrorType.Network,
          message: '网络错误，请稍后再试',
          raw: err,
        } satisfies HttpError)
        if (!options.hideErrorToast) {
          uni.showToast({ icon: 'none', title: httpError.message })
        }
        reject(httpError)
      },
    })
  })
}

/** GET */
export function httpGet<T>(url: string, query?: Record<string, any>, header?: Record<string, any>, options?: Partial<CustomRequestOptions>) {
  return http<T>({ url, query, method: 'GET', header, ...options })
}

/** POST */
export function httpPost<T>(url: string, data?: Record<string, any>, query?: Record<string, any>, header?: Record<string, any>, options?: Partial<CustomRequestOptions>) {
  return http<T>({ url, query, data, method: 'POST', header, ...options })
}

/** PUT */
export function httpPut<T>(url: string, data?: Record<string, any>, query?: Record<string, any>, header?: Record<string, any>, options?: Partial<CustomRequestOptions>) {
  return http<T>({ url, data, query, method: 'PUT', header, ...options })
}

/** DELETE（无请求体，仅 query） */
export function httpDelete<T>(url: string, query?: Record<string, any>, header?: Record<string, any>, options?: Partial<CustomRequestOptions>) {
  return http<T>({ url, query, method: 'DELETE', header, ...options })
}

// 兼容 axios / alova 风格调用
http.get = httpGet
http.post = httpPost
http.put = httpPut
http.delete = httpDelete
http.Get = httpGet
http.Post = httpPost
http.Put = httpPut
http.Delete = httpDelete
