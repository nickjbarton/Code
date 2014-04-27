dir=$1
outdir=${dir}/shared/logs/latest/lts
ENGINE_ID=$(sed 's/.*Found engine //p;d' ${outdir}/lts_engine_prepare_reset_b1.log)
echo "Outputting $ENGINE_ID to ${outdir}/engineAControlFile"
echo $ENGINE_ID > ${outdir}/engineAControlFile
