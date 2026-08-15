import statsapi
import datetime
import boto3
from botocore.exceptions import ClientError
from aws_lambda_powertools import Logger
from aws_lambda_powertools.utilities.typing import LambdaContext
import json
import os
from concurrent.futures import ThreadPoolExecutor, as_completed

logger = Logger(service="baseball-poller")

SNS_TOPIC = os.environ['SNS_TOPIC_ARN']
BUCKET = os.environ['S3_BUCKET']
TEAM_IDS = []

_PUBLISH_WORKERS = 10
_DATE_CHUNK_DAYS = 30


@logger.inject_lambda_context(log_event=False, clear_state=True)
def handler(event: dict, context: LambdaContext):
    global s3, sns
    if os.environ.get("AWS_SAM_LOCAL"):
        endpoint_url = "http://host.docker.internal:4566"
    else:
        endpoint_url = None

    s3  = boto3.client('s3',  endpoint_url=endpoint_url, region_name='us-east-1')
    sns = boto3.client('sns', endpoint_url=endpoint_url, region_name='us-east-1')

    invocation_time = datetime.datetime.fromisoformat(
            event.get('time', datetime.datetime.now(datetime.timezone.utc).isoformat())
    )

    start_date = event.get('start_date') or (invocation_time - datetime.timedelta(days=1)).strftime('%m/%d/%Y')
    end_date = event.get('end_date') or invocation_time.strftime('%m/%d/%Y')

    logger.info("Run Parameters",
                start_date=start_date,
                end_date=end_date)
    run(start_date=start_date, end_date=end_date)


def is_already_processed(game_id: str) -> bool:
    logger.info("S3 config",
        endpoint=s3.meta.endpoint_url,
        bucket=BUCKET,
        key=f'processed/game_id={game_id}'
    )
    logger.info(f'Checking where game {game_id} has already been processed')

    try:
        s3.head_object(
            Bucket=BUCKET,
            Key=f'processed/game_id={game_id}'
        )
        return True
    except ClientError as e:
        if e.response['Error']['Code'] == '404':
            logger.info(f'Game {game_id} not processed, event will be published')
            return False
        raise


def mark_as_processed(game_id: str, game_date: str):
    s3.put_object(
        Bucket=BUCKET,
        Key=f'processed/game_id={game_id}',
        Body=json.dumps({
            'game_id': game_id,
            'game_date': game_date,
            'processed_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'raw_path': f'raw/game_date={game_date}/game_id={game_id}/'
        }),
        ContentType='application/json'
    )


def get_game_ids(start_date, end_date, team_id=''):
    games = statsapi.schedule(
        start_date=start_date,
        end_date=end_date,
        team=team_id
    )
    return [
        {'game_id': g['game_id'], 'game_date': g['game_date']}
            for g in games if g['status'] == 'Final'
    ]


def publish_game_id_message(payload, topic=SNS_TOPIC):
    sns.publish(
        TopicArn=topic,
        Message=json.dumps(payload),
        Subject='game.completed',
        MessageAttributes={
            'event_type': {
                'DataType': 'String',
                'StringValue': 'game.completed'
            }
        }
    )


def process_game_id(payload):
    game_id = payload['game_id']

    if is_already_processed(game_id):
        logger.info("Game already processed, skipping", game_id=game_id)
        return

    try:
        publish_game_id_message(payload)
        mark_as_processed(game_id, payload['game_date'])
        logger.info("Game successfully published", game_id=game_id)
    except Exception:
        logger.exception("Failed to process game", game_id=game_id)
        raise


def _date_chunks(start: datetime.date, end: datetime.date, days: int):
    cursor = start
    while cursor <= end:
        chunk_end = min(cursor + datetime.timedelta(days=days - 1), end)
        yield cursor, chunk_end
        cursor = chunk_end + datetime.timedelta(days=1)


def run(start_date, end_date, team_ids=TEAM_IDS):
    fmt = '%m/%d/%Y'
    start = datetime.datetime.strptime(start_date, fmt).date()
    end = datetime.datetime.strptime(end_date, fmt).date()

    for chunk_start, chunk_end in _date_chunks(start, end, _DATE_CHUNK_DAYS):
        chunk_start_str = chunk_start.strftime(fmt)
        chunk_end_str = chunk_end.strftime(fmt)

        if len(team_ids) > 0:
            game_ids = []
            for team_id in team_ids:
                game_ids.extend(get_game_ids(chunk_start_str, chunk_end_str, team_id))
        else:
            game_ids = get_game_ids(chunk_start_str, chunk_end_str)

        logger.info("Completed games found in chunk",
                    chunk_start=chunk_start_str,
                    chunk_end=chunk_end_str,
                    game_count=len(game_ids))

        with ThreadPoolExecutor(max_workers=_PUBLISH_WORKERS) as executor:
            futures = {executor.submit(process_game_id, gid): gid for gid in game_ids}
            for future in as_completed(futures):
                try:
                    future.result()
                except Exception:
                    logger.exception("Unhandled error processing game", game=futures[future])
