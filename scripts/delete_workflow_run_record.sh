#!/bin/bash

echo "Starting cleanup of all workflow runs..."

# 获取所有 workflow ID
workflow_ids=$(gh workflow list --json id -q '.[].id')

for wf_id in $workflow_ids; do
    echo "Processing workflow ID: $wf_id"

    # 获取该 workflow 所有运行记录（只取 id 和 status）
    runs=$(gh run list --workflow "$wf_id" --json databaseId,status)

    # 遍历所有 runs
    echo "$runs" | jq -c '.[]' | while read -r run; do
        run_id=$(echo "$run" | jq -r '.databaseId')
        status=$(echo "$run" | jq -r '.status')

        echo "Run ID: $run_id | Status: $status"

        # 如果状态是 in_progress 或 queued，先取消
        if [[ "$status" == "in_progress" || "$status" == "queued" ]]; then
            echo "  -> Canceling run $run_id ..."
            gh run cancel $run_id
        fi

        # 删除 run
        echo "  -> Deleting run $run_id ..."
        yes | gh run delete $run_id
    done
done

echo "All workflow runs processed."
