import datetime
import io
import json
import os

import boto3
import pyarrow as pa
import pyarrow.parquet as pq
import statsapi
from aws_lambda_powertools import Logger
from aws_lambda_powertools.utilities.batch import BatchProcessor, EventType, process_partial_response
from aws_lambda_powertools.utilities.data_classes.sqs_event import SQSRecord
from aws_lambda_powertools.utilities.typing import LambdaContext

logger = Logger(service="baseball-play-by-play")
processor = BatchProcessor(event_type=EventType.SQS)

BUCKET = os.environ['S3_BUCKET']


def _s3():
    if os.environ.get("AWS_SAM_LOCAL"):
        return boto3.client('s3', endpoint_url="http://host.docker.internal:4566", region_name='us-east-1')
    return boto3.client('s3')


def _flatten_play_by_play(game_id: int) -> list[dict]:
    data = statsapi.get('game_playByPlay', params={'gamePk': game_id})
    rows = []

    for at_bat in data.get('allPlays', []):
        about   = at_bat.get('about', {})
        matchup = at_bat.get('matchup', {})
        result  = at_bat.get('result', {})

        at_bat_ctx = {
            'game_id':        game_id,
            'at_bat_index':   about.get('atBatIndex'),
            'inning':         about.get('inning'),
            'half_inning':    about.get('halfInning'),
            'batter_id':      matchup.get('batter', {}).get('id'),
            'batter_name':    matchup.get('batter', {}).get('fullName'),
            'bat_side':       matchup.get('batSide', {}).get('code'),
            'pitcher_id':     matchup.get('pitcher', {}).get('id'),
            'pitcher_name':   matchup.get('pitcher', {}).get('fullName'),
            'pitch_hand':     matchup.get('pitchHand', {}).get('code'),
            'result_event':   result.get('event'),
            'result_type':    result.get('type'),
            'is_scoring_play': about.get('isScoringPlay'),
            'away_score':     result.get('awayScore'),
            'home_score':     result.get('homeScore'),
        }

        for event in at_bat.get('playEvents', []):
            details    = event.get('details', {})
            pitch_data = event.get('pitchData', {})
            coords     = pitch_data.get('coordinates', {})
            breaks     = pitch_data.get('breaks', {})
            count      = event.get('count', {})

            rows.append({
                **at_bat_ctx,
                'event_index':      event.get('index'),
                'pitch_number':     event.get('pitchNumber'),
                'is_pitch':         event.get('isPitch', False),
                'event_type':       event.get('type'),
                'play_id':          event.get('playId'),
                'start_time':       event.get('startTime'),
                'end_time':         event.get('endTime'),
                # pitch classification
                'pitch_type_code':  details.get('type', {}).get('code'),
                'pitch_type_desc':  details.get('type', {}).get('description'),
                # outcome
                'call_code':        details.get('call', {}).get('code'),
                'call_description': details.get('description'),
                'is_in_play':       details.get('isInPlay'),
                'is_strike':        details.get('isStrike'),
                'is_ball':          details.get('isBall'),
                'is_out':           details.get('isOut'),
                # velocity & movement
                'start_speed':      pitch_data.get('startSpeed'),
                'end_speed':        pitch_data.get('endSpeed'),
                'pfx_x':            coords.get('pfxX'),
                'pfx_z':            coords.get('pfxZ'),
                # location
                'plate_x':          coords.get('pX'),
                'plate_z':          coords.get('pZ'),
                'zone':             pitch_data.get('zone'),
                'strike_zone_top':  pitch_data.get('strikeZoneTop'),
                'strike_zone_bot':  pitch_data.get('strikeZoneBottom'),
                # spin
                'spin_rate':        breaks.get('spinRate'),
                'spin_direction':   breaks.get('spinDirection'),
                # count when pitch was thrown
                'count_balls':      count.get('balls'),
                'count_strikes':    count.get('strikes'),
                'count_outs':       count.get('outs'),
            })

    return rows


def _write_play_by_play(game_id: str, game_date: str) -> str:
    invocation_time = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    s3_key = f'play-by-play/game_date={game_date}/game_id={game_id}/{invocation_time}.parquet.gzip'

    logger.info("Fetching play by play data", game_id=game_id, game_date=game_date)
    rows = _flatten_play_by_play(int(game_id))
    logger.info("Fetched play by play data", game_id=game_id, row_count=len(rows))

    buf = io.BytesIO()
    pq.write_table(pa.Table.from_pylist(rows), buf, compression='gzip')
    buf.seek(0)

    _s3().put_object(
        Bucket=BUCKET,
        Key=s3_key,
        Body=buf.getvalue(),
        ContentType='application/octet-stream',
    )

    logger.info("Wrote play by play data", s3_key=s3_key)
    return s3_key


def record_handler(record: SQSRecord):
    payload = json.loads(record.decoded_nested_sns_event.message)
    game_id = str(payload['game_id'])
    game_date = payload['game_date']

    logger.append_keys(game_id=game_id)
    try:
        _write_play_by_play(game_id, game_date)
    finally:
        logger.remove_keys(['game_id'])


@logger.inject_lambda_context(log_event=False, clear_state=True)
def lambda_handler(event: dict, context: LambdaContext):
    return process_partial_response(
        event=event,
        record_handler=record_handler,
        processor=processor,
        context=context,
    )
