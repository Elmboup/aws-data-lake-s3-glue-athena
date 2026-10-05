import sys

from awsglue.context import GlueContext
from awsglue.dynamicframe import DynamicFrame
from awsglue.job import Job
from awsglue.transforms import SelectFromCollection
from awsglue.utils import getResolvedOptions
from awsgluedq.transforms import EvaluateDataQuality

from pyspark.context import SparkContext
from pyspark.sql.functions import col, to_timestamp
from pyspark.sql.types import DecimalType


args = getResolvedOptions(
    sys.argv,
    [
        "JOB_NAME",
        "RAW_DATABASE",
        "RAW_TABLE",
        "SILVER_PATH",
        "QUARANTINE_PATH",
    ],
)

sc = SparkContext.getOrCreate()
glue_context = GlueContext(sc)
spark = glue_context.spark_session

job = Job(glue_context)
job.init(args["JOB_NAME"], args)


# 1. Read raw data via the Glue Data Catalog.
raw_dyf = glue_context.create_dynamic_frame.from_catalog(
    database=args["RAW_DATABASE"],
    table_name=args["RAW_TABLE"],
    transformation_ctx="raw_transactions",
)

raw_df = raw_dyf.toDF()

print("===== RAW ROW COUNT =====")
print(raw_df.count())


# 2. Technical transformations.
prepared_df = (
    raw_df
    .dropDuplicates(["transaction_id"])
    .withColumn("amount", col("amount").cast(DecimalType(18, 2)))
    .withColumn(
        "timestamp",
        to_timestamp(col("timestamp"), "yyyy-MM-dd'T'HH:mm:ss"),
    )
)

print("===== PREPARED ROW COUNT =====")
print(prepared_df.count())

prepared_dyf = DynamicFrame.fromDF(
    prepared_df,
    glue_context,
    "prepared_transactions",
)


# 3. Data Quality rules.
dq_ruleset = """
Rules = [
    IsComplete "transaction_id",
    IsComplete "customer_id",
    IsComplete "account_id",
    IsComplete "amount",
    ColumnValues "amount" > 0,
    IsComplete "currency",
    IsComplete "timestamp"
]
"""

dq_results = EvaluateDataQuality().process_rows(
    frame=prepared_dyf,
    ruleset=dq_ruleset,
    publishing_options={
        "dataQualityEvaluationContext": "banking_transactions_dq",
        "enableDataQualityCloudWatchMetrics": False,
        "enableDataQualityResultsPublishing": False,
    },
    additional_options={
        "performanceTuning.caching": "CACHE_NOTHING",
        "publishAggregatedMetrics.status": "ENABLED",
    },
)


# 4. Row-level outcomes.
row_outcomes = SelectFromCollection.apply(
    dfc=dq_results,
    key="rowLevelOutcomes",
    transformation_ctx="row_level_outcomes",
)

dq_df = row_outcomes.toDF()

valid_df = dq_df.filter(
    col("DataQualityEvaluationResult") == "Passed"
)

quarantine_df = dq_df.filter(
    col("DataQualityEvaluationResult") == "Failed"
)

print("===== VALID ROW COUNT =====")
print(valid_df.count())

print("===== QUARANTINE ROW COUNT =====")
print(quarantine_df.count())


# 5. Rule-level results.
rule_outcomes = SelectFromCollection.apply(
    dfc=dq_results,
    key="ruleOutcomes",
    transformation_ctx="rule_outcomes",
)

print("===== DATA QUALITY RULE RESULTS =====")
rule_outcomes.toDF().show(truncate=False)


# 6. Remove technical DQ metadata from the trusted Silver dataset.
dq_columns = [
    "DataQualityRulesPass",
    "DataQualityRulesFail",
    "DataQualityRulesSkip",
    "DataQualityEvaluationResult",
]

silver_df = valid_df.drop(*dq_columns)


# 7. Write valid records to Silver.
(
    silver_df.write
    .mode("overwrite")
    .partitionBy("year", "month", "day")
    .parquet(args["SILVER_PATH"])
)


# 8. Preserve failed records and DQ diagnostics in Quarantine.
(
    quarantine_df.write
    .mode("overwrite")
    .partitionBy("year", "month", "day")
    .parquet(args["QUARANTINE_PATH"])
)

job.commit()
