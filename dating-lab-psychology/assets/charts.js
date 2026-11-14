// 恋爱好感度实验室 · 心理学理论依据文档 图表逻辑
(function () {
  var style = getComputedStyle(document.documentElement);
  var accent = style.getPropertyValue('--accent').trim();
  var accent2 = style.getPropertyValue('--accent2').trim();
  var ink = style.getPropertyValue('--ink').trim();
  var muted = style.getPropertyValue('--muted').trim();
  var rule = style.getPropertyValue('--rule').trim();
  var bg2 = style.getPropertyValue('--bg2').trim();

  var baseFont = 'CrimsonPro, "PingFang SC", "Microsoft YaHei", sans-serif';

  // --- Chart 1: 六维度权重水平条形图 ---
  var weightsEl = document.getElementById('chart-weights');
  if (weightsEl) {
    var weightsChart = echarts.init(weightsEl, null, { renderer: 'svg' });
    weightsChart.setOption({
      animation: false,
      textStyle: { fontFamily: baseFont },
      grid: { left: 96, right: 60, top: 16, bottom: 30 },
      tooltip: {
        trigger: 'axis',
        axisPointer: { type: 'shadow' },
        appendToBody: true,
        formatter: function (params) {
          var p = params[0];
          return p.name + '：权重 ' + Number(p.value).toFixed(2);
        }
      },
      xAxis: {
        type: 'value',
        min: 0,
        max: 0.24,
        axisLabel: { color: muted, fontFamily: 'DMMono, monospace' },
        splitLine: { lineStyle: { color: rule } },
        axisLine: { show: false }
      },
      yAxis: {
        type: 'category',
        inverse: true,
        data: ['回应性', '激情', '安全感', '亲密', '承诺', '沟通'],
        axisLabel: { color: ink, fontSize: 13, fontWeight: 600 },
        axisTick: { show: false },
        axisLine: { show: false }
      },
      series: [
        {
          type: 'bar',
          barWidth: 22,
          data: [0.10, 0.15, 0.15, 0.20, 0.20, 0.20],
          itemStyle: {
            borderRadius: [0, 11, 11, 0],
            color: function (params) {
              var high = params.value >= 0.20;
              return high
                ? { type: 'linear', x: 0, y: 0, x2: 1, y2: 0, colorStops: [{ offset: 0, color: accent }, { offset: 1, color: accent2 }] }
                : accent2 + '99';
            }
          },
          label: {
            show: true,
            position: 'right',
            fontFamily: 'DMMono, monospace',
            fontSize: 12,
            color: muted,
            formatter: function (p) { return p.value.toFixed(2); }
          }
        }
      ]
    });
    window.addEventListener('resize', function () { weightsChart.resize(); });
  }

  // --- Chart 2: Sternberg 典型爱情类型三成分雷达 ---
  var radarEl = document.getElementById('chart-radar');
  if (radarEl) {
    var radarChart = echarts.init(radarEl, null, { renderer: 'svg' });
    radarChart.setOption({
      animation: false,
      textStyle: { fontFamily: baseFont },
      tooltip: { trigger: 'item', appendToBody: true },
      legend: {
        bottom: 0,
        textStyle: { color: ink, fontSize: 12 },
        itemWidth: 14,
        itemHeight: 8
      },
      radar: {
        center: ['50%', '46%'],
        radius: '62%',
        indicator: [
          { name: '亲密 Intimacy', max: 100 },
          { name: '激情 Passion', max: 100 },
          { name: '承诺 Commitment', max: 100 }
        ],
        axisName: { color: ink, fontSize: 12, fontWeight: 600 },
        splitLine: { lineStyle: { color: rule } },
        splitArea: { areaStyle: { color: ['transparent', 'rgba(232,97,140,0.03)'] } },
        axisLine: { lineStyle: { color: rule } }
      },
      series: [
        {
          type: 'radar',
          symbolSize: 5,
          data: [
            {
              name: '💫 完美之爱',
              value: [92, 88, 90],
              lineStyle: { color: accent, width: 2.5 },
              itemStyle: { color: accent },
              areaStyle: { color: accent, opacity: 0.10 }
            },
            {
              name: '🌹 浪漫之爱',
              value: [88, 90, 42],
              lineStyle: { color: accent2, width: 2 },
              itemStyle: { color: accent2 },
              areaStyle: { color: accent2, opacity: 0.07 }
            },
            {
              name: '🏠 伴侣之爱',
              value: [86, 44, 88],
              lineStyle: { color: muted, width: 2 },
              itemStyle: { color: muted },
              areaStyle: { color: muted, opacity: 0.06 }
            },
            {
              name: '🎡 炽热之爱',
              value: [42, 90, 86],
              lineStyle: { color: accent + '88', width: 2, type: 'dashed' },
              itemStyle: { color: accent + '88' },
              areaStyle: { color: accent, opacity: 0.04 }
            }
          ]
        }
      ]
    });
    window.addEventListener('resize', function () { radarChart.resize(); });
  }
})();
