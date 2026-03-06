import type { Endpoint } from 'payload'

// Types for upstream API response
interface UpstreamCharacterRecord {
  poolId: string
  poolName: string
  pool_type: string
  charId: string
  charName: string
  rarity: number
  isFree: boolean
  isNew: boolean
  gachaTs: string
  seqId: string
}

interface UpstreamWeaponRecord {
  poolId: string
  poolName: string
  weaponId: string
  weaponName: string
  weaponType: string
  rarity: number
  isNew: boolean
  gachaTs: string
  seqId: string
}

// Unified record type (normalized to match character structure)
interface UnifiedRecord {
  poolId: string
  poolName: string
  pool_type: string
  itemId: string // charId or weaponId
  itemName: string // charName or weaponName
  itemType?: string // weaponType if weapon
  rarity: number
  isFree: boolean
  isNew: boolean
  gachaTs: string
  seqId: string
}

interface UpstreamPageResponse {
  code: number
  msg: string
  data: {
    list: Array<UpstreamCharacterRecord | UpstreamWeaponRecord>
    hasMore: boolean
  }
}

// Transformed response (merged from all pool types, no pagination)
interface TransformedResponse {
  code: number
  msg: string
  data: {
    list: UnifiedRecord[]
    totalRecords: number
  }
}

// Pool configurations
interface PoolConfig {
  type: string
  endpoint: 'char' | 'weapon'
  paramKey: 'pool_type' | 'pool_id'
}

const ALL_POOL_CONFIGS: PoolConfig[] = [
  {
    type: 'E_CharacterGachaPoolType_Beginner',
    endpoint: 'char',
    paramKey: 'pool_type',
  },
  {
    type: 'E_CharacterGachaPoolType_Special',
    endpoint: 'char',
    paramKey: 'pool_type',
  },
  {
    type: 'E_CharacterGachaPoolType_Standard',
    endpoint: 'char',
    paramKey: 'pool_type',
  },
  {
    type: 'weponbox_1_0_1',
    endpoint: 'weapon',
    paramKey: 'pool_id',
  },
  {
    type: 'weaponbox_constant_2',
    endpoint: 'weapon',
    paramKey: 'pool_id',
  },
  {
    type: 'weponbox_1_0_3',
    endpoint: 'weapon',
    paramKey: 'pool_id',
  },
  {
    type: 'weponbox_1_0_2',
    endpoint: 'weapon',
    paramKey: 'pool_id',
  },
]

/**
 * Masks sensitive token values in a string
 * Replaces token with asterisks, keeping first 4 and last 4 characters visible
 */
function maskToken(token: string | null): string {
  if (!token || token.length <= 8) {
    return '***'
  }
  const visibleStart = token.substring(0, 4)
  const visibleEnd = token.substring(token.length - 4)
  const masked = '*'.repeat(Math.max(0, token.length - 8))
  return `${visibleStart}${masked}${visibleEnd}`
}

/**
 * Masks token parameters in a URL string for logging
 */
function maskUrl(url: string): string {
  try {
    const urlObj = new URL(url)
    // Mask token parameter
    if (urlObj.searchParams.has('token')) {
      const token = urlObj.searchParams.get('token')
      urlObj.searchParams.set('token', maskToken(token))
    }
    // Mask u8_token parameter
    if (urlObj.searchParams.has('u8_token')) {
      const token = urlObj.searchParams.get('u8_token')
      urlObj.searchParams.set('u8_token', maskToken(token))
    }
    return urlObj.toString()
  } catch {
    // If URL parsing fails, mask token patterns directly
    return url.replace(/([?&](?:token|u8_token)=)([^&]+)/g, (match, param, token) => {
      return `${param}${maskToken(token)}`
    })
  }
}

/**
 * POST /api/tracker-import
 * Fetches gacha history from ef-webview.gryphline.com
 * - Automatically crawls ALL pool types (Character: Beginner, Special, Standard + Weapon: weponbox_1_0_1)
 * - Paginates each pool type until hasMore=false
 * - Merges and dedupes all records
 * - Returns transformed response without pagination params
 */
export const trackerImportEndpoint: Endpoint = {
  path: '/tracker-import',
  method: 'post',
  handler: async (req) => {
    try {
      // 1. Parse and validate request body
      const body = await req?.json?.()

      if (!body || typeof body !== 'object') {
        return Response.json({ error: 'Invalid request body' }, { status: 400 })
      }

      const { url } = body

      // 2. Validate URL exists and is a string
      if (!url || typeof url !== 'string') {
        return Response.json({ error: 'Missing or invalid "url" field' }, { status: 400 })
      }

      const urlTrimmed = url.trim()

      // 3. Validate URL length (prevent abuse)
      if (urlTrimmed.length === 0 || urlTrimmed.length > 2048) {
        return Response.json({ error: 'URL must be between 1-2048 characters' }, { status: 400 })
      }

      // 4. Parse URL
      let parsedUrl: URL
      try {
        parsedUrl = new URL(urlTrimmed)
      } catch (error) {
        return Response.json({ error: 'Invalid URL format' }, { status: 400 })
      }

      // 5. Validate protocol is HTTPS
      if (parsedUrl.protocol !== 'https:') {
        return Response.json({ error: 'URL must use HTTPS protocol' }, { status: 400 })
      }

      // 6. Validate hostname
      if (parsedUrl.hostname !== 'ef-webview.gryphline.com') {
        return Response.json(
          { error: 'URL must be from ef-webview.gryphline.com' },
          { status: 400 },
        )
      }

      // 8. Extract required params from original URL
      const token = parsedUrl.searchParams.get('token') || parsedUrl.searchParams.get('u8_token')
      const serverId =
        parsedUrl.searchParams.get('server_id') || parsedUrl.searchParams.get('server')
      const lang = parsedUrl.searchParams.get('lang') || 'vi-vn' // Default to vi-vn if not provided
      const initialSeqId = parsedUrl.searchParams.get('seq_id') // i dont care initial seq_id

      // Validate required params
      if (!token) {
        return Response.json({ error: 'Missing token parameter in URL' }, { status: 400 })
      }
      if (!serverId) {
        return Response.json({ error: 'Missing server_id parameter in URL' }, { status: 400 })
      }

      // 9. Helper function to normalize records
      const normalizeRecord = (
        record: UpstreamCharacterRecord | UpstreamWeaponRecord,
        poolType: string,
      ): UnifiedRecord => {
        // Check if it's a weapon record
        if ('weaponId' in record) {
          return {
            poolId: record.poolId,
            poolName: record.poolName,
            pool_type: poolType,
            itemId: record.weaponId,
            itemName: record.weaponName,
            itemType: record.weaponType,
            rarity: record.rarity,
            isFree: false,
            isNew: record.isNew,
            gachaTs: record.gachaTs,
            seqId: record.seqId,
          }
        }

        // Character record
        return {
          poolId: record.poolId,
          poolName: record.poolName,
          pool_type: poolType,
          itemId: record.charId,
          itemName: record.charName,
          rarity: record.rarity,
          isFree: record.isFree,
          isNew: record.isNew,
          gachaTs: record.gachaTs,
          seqId: record.seqId,
        }
      }

      // 10. Helper function to build normalized page URL for a specific pool config and seq_id
      const buildPageUrl = (config: PoolConfig, seqId: string | null): string => {
        // Build URL from scratch with normalized format
        const baseUrl = `https://ef-webview.gryphline.com/api/record/${config.endpoint}`
        const pageUrl = new URL(baseUrl)

        // Set required params in correct order
        pageUrl.searchParams.set('lang', lang)
        pageUrl.searchParams.set(config.paramKey, config.type)
        pageUrl.searchParams.set('token', token)
        pageUrl.searchParams.set('server_id', serverId)

        // Add seq_id only if provided (for pagination)
        if (seqId) {
          pageUrl.searchParams.set('seq_id', seqId)
        }

        return pageUrl.toString()
      }

      // 11. Fetch all records from all pool configs
      const allRecords: UnifiedRecord[] = []
      let firstCode = 0
      let firstMsg = ''

      for (const config of ALL_POOL_CONFIGS) {
        req.payload.logger.info(
          `[TrackerImport] Fetching pool: ${config.type} (${config.endpoint})`,
        )
        let currentSeqId = null
        let pageCount = 0
        const maxPages = 200 // Safety guard per pool type

        while (true) {
          pageCount++
          const pageUrl = buildPageUrl(config, currentSeqId)
          req.payload.logger.info(`[TrackerImport] Fetching page: ${maskUrl(pageUrl)}`)

          // Fetch page
          let upstreamResponse = await fetch(pageUrl, {
            method: 'GET',
            headers: {
              Accept: 'application/json',
              'User-Agent':
                'Mozilla/5.0 (Windows NT 6.2; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) QtWebEngine/5.15.8 Chrome/87.0.4280.144 Safari/537.36 PC/WIN/HGSDK HGWebPC/1.30.1',
              'accept-language': 'vi-VN',
            },
            signal: AbortSignal.timeout(10000), // 10 seconds per request
          })

          if (!upstreamResponse.ok) {
            throw new Error(
              `[TrackerImport] ${config.type} page ${pageCount} returned ${upstreamResponse.status}`,
            )
          }

          // Parse JSON
          let page = await upstreamResponse.json()

          // Store first successful response code/msg
          if (firstCode === 0 && page.code !== undefined) {
            firstCode = page.code
            firstMsg = page.msg || ''
          }

          // Validate shape
          if (!page.data?.list || !Array.isArray(page.data.list)) {
            throw new Error(
              `[TrackerImport] ${config.type} page ${pageCount} returned invalid data`,
            )
          }

          for (const item of page.data.list) {
            if (item.seqId) {
              allRecords.push(normalizeRecord(item, config.type))
            }
          }

          req.payload.logger.info(
            `[TrackerImport] ${config.type} page ${pageCount}: ${page.data.list.length} items, hasMore=${page.data.hasMore}`,
          )

          // Check stop conditions
          const last = page.data.list[page.data.list.length - 1]
          if (
            page.data.hasMore !== true ||
            page.data.list.length === 0 ||
            !last?.seqId ||
            last.seqId === currentSeqId ||
            pageCount >= maxPages
          ) {
            break
          }

          currentSeqId = last.seqId
        }

        req.payload.logger.info(
          `[TrackerImport] ${config.type} complete: ${pageCount} pages fetched`,
        )
      }

      // 12. Check if we got any data
      if (allRecords.length === 0) {
        return Response.json({ error: 'No data fetched from any pool type' }, { status: 502 })
      }

      // 13. Return transformed response
      const transformedResponse: TransformedResponse = {
        code: firstCode,
        msg: firstMsg,
        data: {
          list: allRecords,
          totalRecords: allRecords.length,
        },
      }

      req.payload.logger.info(`[TrackerImport] Total records: ${allRecords.length}`)
      return Response.json(transformedResponse)
    } catch (error: any) {
      // Mask sensitive information in error logs
      const errorMessage = error?.message || error?.toString() || String(error) || 'Unknown error'
      const maskedMessage = errorMessage.includes('http')
        ? maskUrl(errorMessage)
        : errorMessage.replace(
            /(token|u8_token)=([^&\s]+)/gi,
            (_match: string, param: string, token: string) => {
              return `${param}=${maskToken(token)}`
            },
          )
      req.payload.logger.error('[TrackerImport] Error in trackerImportEndpoint:', {
        ...error,
        message: maskedMessage,
        stack: error?.stack,
      })
      return Response.json({ error: 'Internal server error' }, { status: 500 })
    }
  },
}
