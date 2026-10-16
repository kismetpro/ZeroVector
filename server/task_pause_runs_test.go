package server

import (
	"context"
	"testing"

	"github.com/Autumn-27/artex/agent"
)

// 暂停一个任务时，任务级的 agent 运行（reporter 触发器、复测会话）必须一起被取消。
// 它们此前只按会话键登记取消句柄，暂停只取消了主 agent 的那一轮，于是页面显示已暂停
// 后 reporter 仍继续产出。registerTaskRun / cancelTaskRuns 是这条链路的唯一入口。
func TestCancelTaskRunsReachesEveryRegisteredRun(t *testing.T) {
	s := &Server{}
	var cancelledA, cancelledB int
	releaseA := s.registerTaskRun(7, func(error) { cancelledA++ })
	releaseB := s.registerTaskRun(7, func(error) { cancelledB++ })
	otherRelease := s.registerTaskRun(9, func(error) { t.Error("另一个任务的运行不应被取消") })
	defer otherRelease()

	if n := s.cancelTaskRuns("7", agent.AbortPausedByUser); n != 2 || cancelledA != 1 || cancelledB != 1 {
		t.Fatalf("cancelTaskRuns n=%d cancelledA=%d cancelledB=%d，期望 2/1/1", n, cancelledA, cancelledB)
	}
	releaseA()
	releaseB()
	if n := s.cancelTaskRuns("7", agent.AbortPausedByUser); n != 0 {
		t.Fatalf("运行结束后不应再有可取消的句柄，得到 %d", n)
	}
}

// 暂停中的任务：触发事件既不能丢，也不能在暂停期间启动新的 agent 回合 —— 留在队列里，
// 等恢复时由 pumpAllTriggers 放行。
func TestTriggerPumpHoldsFiresOfPausedTask(t *testing.T) {
	e := NewEngine(nil)
	e.paused.Store("7", true)
	s := &Server{
		engine:        e,
		ctx:           context.Background(),
		triggerQ:      map[string][]triggeredRun{},
		triggerActive: map[string]int{},
		triggerCfg:    map[string]triggerBehavior{},
		taskRuns:      map[string]map[uint64]context.CancelCauseFunc{},
	}
	s.triggerQ["reporter"] = []triggeredRun{{agentKey: "reporter", title: "t", message: "m", taskID: 7, mergeable: true}}

	s.queueMu.Lock()
	s.pumpLocked("reporter")
	s.queueMu.Unlock()

	if got := s.triggerActive["reporter"]; got != 0 {
		t.Fatalf("暂停任务不应启动新的 reporter 回合，triggerActive=%d", got)
	}
	if got := len(s.triggerQ["reporter"]); got != 1 {
		t.Fatalf("事件必须留在队列里等恢复，队列长度=%d", got)
	}
	if !s.taskPaused(7) {
		t.Fatal("taskPaused 应反映引擎的暂停状态")
	}
	if s.taskPaused(0) {
		t.Fatal("非任务级触发（taskID=0）不应被当作暂停")
	}
}
