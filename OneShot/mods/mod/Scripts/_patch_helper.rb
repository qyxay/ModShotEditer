# ============================================================
#  _patch_helper.rb — 统一补丁安装工具 (PatchHelper)
#
#  各 mod 脚本需要"等待某个游戏类定义完成后, 用 Module#prepend
#  挂上补丁模块"。原实现每个文件重复一份 TracePoint(:end) 样板,
#  本文件统一封装。
#
#  用法:
#    PatchHelper.install('Interpreter', methods: [:execute_command]) do |k|
#      k.prepend(SkipAllDialoguePatch)
#    end
#
#  语义与原样板完全一致:
#    * TracePoint(:end) 异步监听, 目标类定义完成且指定方法就绪后才触发
#    * 触发后执行 block(通常 prepend), 然后 disable 停止监听
#    * 任何异常被吞掉(不影响游戏启动)
#  _ 开头保证按文件名排序最先加载(在 dev_settings 等使用方之前)
# ============================================================

module PatchHelper
  # 等待指定类定义完成后执行 block
  #  class_name: 类名字符串, 如 'Interpreter'
  #  methods:    必须全部就绪的方法名数组, 如 [:execute_command]
  #  block:      收到类对象, 通常 k.prepend(SomePatch)
  def self.install(class_name, methods: [], &block)
    trace = TracePoint.trace(:end) do |tp|
      begin
        if tp.self.is_a?(Class) && tp.self.name == class_name &&
           methods.all? { |m| tp.self.method_defined?(m) }
          block.call(tp.self)
          trace.disable
        end
      rescue StandardError
        # 忽略异常, 继续监听
      end
    end
    trace
  end
end
