import os
import json
import time
import requests

def fetch_ulsan_metro_buildings():
    key_path = os.path.abspath('data/api_keys.json')
    with open(key_path, 'r', encoding='utf-8') as f:
        key = json.load(f)['vworld_api_key']

    hubs = [
        {'name': '남구 삼산/달동 중심 상업업무지구', 'w': 129.33, 's': 35.53, 'e': 129.35, 'n': 35.55, 'target_max': 1200},
        {'name': '중구 성남/태화강변 역사문화지구', 'w': 129.31, 's': 35.55, 'e': 129.33, 'n': 35.57, 'target_max': 1000},
        {'name': '중구 우정혁신도시 행정업무지구', 'w': 129.33, 's': 35.56, 'e': 129.35, 'n': 35.58, 'target_max': 800},
        {'name': '동구 HD현대중공업 조선단지/방어진', 'w': 129.41, 's': 35.49, 'e': 129.43, 'n': 35.51, 'target_max': 800},
        {'name': '동구 일산해수욕장/대왕암 테마권역', 'w': 129.42, 's': 35.51, 'e': 129.44, 'n': 35.53, 'target_max': 600},
        {'name': '온산 국가산업단지 중화학 콤플렉스', 'w': 129.34, 's': 35.43, 'e': 129.36, 'n': 35.45, 'target_max': 600},
        {'name': 'KTX 울산역세권 복합환승도시', 'w': 129.13, 's': 35.54, 'e': 129.15, 'n': 35.56, 'target_max': 500}
    ]

    url = 'https://api.vworld.kr/req/data'
    raw_dir = os.path.abspath('data/raw/ulsan_metro_60km/buildings')
    os.makedirs(raw_dir, exist_ok=True)
    out_file = os.path.join(raw_dir, 'vworld_metro_hubs_raw.json')

    all_features = []
    seen_ids = set()

    mugeo_path = os.path.abspath('data/raw/ulsan_uc_west/buildings/vworld_full_region_buildings.json')
    if os.path.exists(mugeo_path):
        with open(mugeo_path, 'r', encoding='utf-8') as f:
            m_data = json.load(f)
            for feat in m_data.get('features', []):
                sn = feat.get('properties', {}).get('bd_mgt_sn', '')
                if sn:
                    seen_ids.add(sn)
                all_features.append(feat)
        print(f'Loaded {len(all_features)} initial buildings from Mugeo (Ulsan Univ) base cache.')

    api_call_count = 0
    start_time = time.time()

    for hub in hubs:
        h_name = hub['name']
        w, s, e, n = hub['w'], hub['s'], hub['e'], hub['n']
        geom = f'BOX({w},{s},{e},{n})'
        target_max = hub['target_max']

        print(f'Fetching {h_name}...')
        page = 1
        hub_added = 0

        while True:
            params = {
                'service': 'data',
                'request': 'GetFeature',
                'data': 'LT_C_SPBD',
                'key': key,
                'format': 'json',
                'geometry': 'true',
                'attribute': 'true',
                'crs': 'EPSG:4326',
                'geomFilter': geom,
                'page': page,
                'size': 100
            }
            api_call_count += 1
            try:
                resp = requests.get(url, params=params, timeout=15)
                if resp.status_code != 200:
                    print(f'  HTTP {resp.status_code} on page {page}')
                    break

                r_json = resp.json()
                resp_body = r_json.get('response', {})
                if resp_body.get('status') != 'OK':
                    print(f'  Status {resp_body.get("status")} on page {page}')
                    break

                feats = resp_body.get('result', {}).get('featureCollection', {}).get('features', [])
                if not feats:
                    break

                for feat in feats:
                    sn = feat.get('properties', {}).get('bd_mgt_sn', '')
                    if sn and sn in seen_ids:
                        continue
                    if sn:
                        seen_ids.add(sn)
                    all_features.append(feat)
                    hub_added += 1

                if len(feats) < 100 or hub_added >= target_max:
                    break

                page += 1
                time.sleep(0.08)
            except Exception as ex:
                print(f'  Exception on page {page}: {ex}')
                break

        print(f'  -> {h_name}: fetched {hub_added} buildings (Total calls so far: {api_call_count})')

    with open(out_file, 'w', encoding='utf-8') as f:
        json.dump({'type': 'FeatureCollection', 'total_count': len(all_features), 'features': all_features}, f, ensure_ascii=False)

    elapsed = time.time() - start_time
    print(f'FINISHED! Total buildings: {len(all_features)} | Total API calls: {api_call_count} in {elapsed:.1f}s')

if __name__ == '__main__':
    fetch_ulsan_metro_buildings()
