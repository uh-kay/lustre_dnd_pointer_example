import gleam/dict
import gleam/dynamic
import gleam/dynamic/decode
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{Some}
import gleam/result
import lustre
import lustre/attribute
import lustre/element
import lustre/element/html
import lustre/event

pub fn main() -> Nil {
  let app = lustre.simple(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)

  Nil
}

// MODEL ----------------------------------------------------------------------

type Model {
  Model(
    dragged_task: option.Option(DraggedTask),
    hovered_column: option.Option(DropTarget),
    task_columns: dict.Dict(ColumnType, List(Task)),
  )
}

type Task {
  Task(id: Int, title: String)
}

type DraggedTask {
  DraggedTask(
    task: Task,
    from: ColumnType,
    height: Int,
    width: Int,
    pointer_x: Int,
    pointer_y: Int,
    offset_x: Int,
    offset_y: Int,
  )
}

type DropTarget {
  DropTarget(to: ColumnType, index: Int)
}

type ColumnType {
  ToDo
  InProgress
  Done
}

type Message {
  UserPickedUpTask(
    task: Task,
    from: ColumnType,
    width: Int,
    height: Int,
    pointer_x: Int,
    pointer_y: Int,
    offset_x: Int,
    offset_y: Int,
  )
  UserMovedPointer(pointer_x: Int, pointer_y: Int)
  UserDroppedTask
  UserDraggedOverColumn(to: ColumnType)
  UserDraggedOverTask(to: ColumnType, index: Int)
  UserCancelledDrag
}

fn init(_) {
  Model(
    dragged_task: option.None,
    task_columns: dict.new()
      |> dict.insert(ToDo, [
        Task(1, "Reinvent universe"),
      ])
      |> dict.insert(InProgress, [Task(2, "Reinvent wheel")])
      |> dict.insert(Done, [
        Task(3, "Play Chesshire"),
        Task(4, "Make drag and drop using Lustre works"),
      ]),
    hovered_column: option.None,
  )
}

// UPDATE ---------------------------------------------------------------------

fn update(model: Model, message: Message) {
  case message {
    UserDroppedTask ->
      case model.dragged_task, model.hovered_column {
        Some(dragged_task), Some(drop_target) -> {
          let from = dragged_task.from
          let dragged_task = dragged_task.task
          let to = drop_target.to
          let from_tasks =
            dict.get(model.task_columns, from) |> result.unwrap([])

          // Find the original index before the filtering which causes the task
          // index to shift.
          let original_index =
            from_tasks
            |> list.take_while(fn(t) { t.id != dragged_task.id })
            |> list.length()

          // Let ["A", "B", "C", "D"] as task column. When we try moving B to
          // between C and D, we move it to index 3. But after filtering, the task
          // index shift and C is at index 1 and D at 2. Moving to index 3 would
          // place it at the end, not between C and D. That's why when the drop
          // target's index is bigger than the original, we substract one.
          let insert_index = case from == to {
            True if drop_target.index > original_index -> drop_target.index - 1
            _ -> drop_target.index
          }

          let task_columns = case dict.get(model.task_columns, from) {
            Ok(tasks) -> {
              let tasks =
                list.filter(tasks, fn(task) { task.id != dragged_task.id })
              dict.insert(model.task_columns, from, tasks)
            }
            Error(_) -> model.task_columns
          }

          let task_columns = case dict.get(task_columns, to) {
            Ok(tasks) -> {
              let #(before, after) = list.split(tasks, insert_index)
              let tasks = list.append(before, [dragged_task, ..after])
              dict.insert(task_columns, to, tasks)
            }
            Error(_) -> model.task_columns
          }

          Model(
            dragged_task: option.None,
            task_columns:,
            hovered_column: option.None,
          )
        }
        _, _ -> cancel_drag(model)
      }

    UserDraggedOverTask(to:, index:) -> {
      let model = Model(..model, hovered_column: Some(DropTarget(to, index)))

      model
    }

    UserDraggedOverColumn(to:) ->
      case model.dragged_task, model.hovered_column {
        option.None, _ -> model
        _, Some(DropTarget(to: current, ..)) if current == to -> model
        Some(_), _ -> {
          let index =
            dict.get(model.task_columns, to) |> result.unwrap([]) |> list.length
          Model(..model, hovered_column: option.Some(DropTarget(to:, index:)))
        }
      }

    UserPickedUpTask(
      task:,
      from:,
      height:,
      pointer_x:,
      pointer_y:,
      offset_x:,
      offset_y:,
      width:,
    ) -> {
      let model =
        Model(
          ..model,
          dragged_task: Some(DraggedTask(
            task:,
            from:,
            height:,
            pointer_x:,
            pointer_y:,
            offset_x:,
            offset_y:,
            width:,
          )),
        )

      model
    }

    UserMovedPointer(pointer_x:, pointer_y:) -> {
      let model = case model.dragged_task {
        Some(dragged_task) ->
          Model(
            ..model,
            dragged_task: Some(
              DraggedTask(..dragged_task, pointer_x:, pointer_y:),
            ),
          )
        option.None -> model
      }

      model
    }

    UserCancelledDrag -> cancel_drag(model)
  }
}

fn cancel_drag(model: Model) {
  Model(..model, dragged_task: option.None, hovered_column: option.None)
}

// VIEW -----------------------------------------------------------------------

fn view(model: Model) -> element.Element(_) {
  html.div(
    [
      attribute.class("flex flex-col p-4 gap-4 min-h-screen select-none"),
      event.on("pointermove", {
        use x <- decode.field("clientX", decode.float)
        use y <- decode.field("clientY", decode.float)
        decode.success(UserMovedPointer(float.truncate(x), float.truncate(y)))
      }),
      event.on("pointerup", decode.success(UserDroppedTask)),
      event.on("pointercancel", decode.success(UserCancelledDrag)),
    ],
    [
      html.h1([attribute.class("text-2xl")], [html.text("Lustre Kanban Board")]),
      html.div([attribute.class("flex gap-4")], [
        task_column_view(
          "To Do",
          ToDo,
          model.task_columns,
          model.dragged_task,
          model.hovered_column,
        ),
        task_column_view(
          "In Progress",
          InProgress,
          model.task_columns,
          model.dragged_task,
          model.hovered_column,
        ),
        task_column_view(
          "Done",
          Done,
          model.task_columns,
          model.dragged_task,
          model.hovered_column,
        ),

        dragged_task_view(model.dragged_task),
      ]),
    ],
  )
}

fn dragged_task_view(dragged_task: option.Option(DraggedTask)) {
  case dragged_task {
    Some(dragged_task) ->
      html.div(
        [
          attribute.class(
            "fixed z-50 border p-2 rounded-md pointer-events-none",
          ),
          attribute.style(
            "left",
            int.to_string(dragged_task.pointer_x - dragged_task.offset_x)
              <> "px",
          ),
          attribute.style(
            "top",
            int.to_string(dragged_task.pointer_y - dragged_task.offset_y)
              <> "px",
          ),
          attribute.style("width", int.to_string(dragged_task.width) <> "px"),
        ],
        [html.p([], [html.text(dragged_task.task.title)])],
      )
    option.None -> element.none()
  }
}

fn task_column_view(
  column_title: String,
  column_type: ColumnType,
  tasks: dict.Dict(ColumnType, List(Task)),
  dragged_task: option.Option(DraggedTask),
  hovered_column: option.Option(DropTarget),
) {
  let tasks = case dict.get(tasks, column_type) {
    Ok(tasks) -> tasks
    Error(_) -> []
  }
  let dragged_id = case dragged_task {
    Some(dragged_task) -> {
      dragged_task.task.id
    }
    option.None -> -1
  }

  let tasks =
    list.index_map(tasks, fn(task, index) {
      task_view(task.id, task.title, column_type, dragged_id == task.id, index)
    })

  let tasks = case hovered_column, dragged_task {
    Some(DropTarget(hovered_type, index)), Some(DraggedTask(height:, ..))
      if hovered_type == column_type
    -> {
      let #(before, after) = list.split(tasks, index)
      list.append(before, [placeholder_view(height), ..after])
    }
    _, _ -> {
      tasks
    }
  }

  html.div(
    [
      attribute.class("border p-4 rounded-md w-64 min-h-40"),
      event.on(
        "pointermove",
        decode.success(UserDraggedOverColumn(column_type)),
      ),
    ],
    [
      html.h2([attribute.class("mb-2")], [html.text(column_title)]),
      html.ul([attribute.class("flex flex-col gap-2 min-h-40")], tasks),
    ],
  )
}

fn task_view(
  task_id: Int,
  task_title: String,
  column_type: ColumnType,
  dragged: Bool,
  index: Int,
) {
  html.li(
    [
      attribute.class("border p-2 rounded-md hover:cursor-grab max-w-64"),
      // Sets touch action to none to prevent the default touch behavior of
      // scrolling or zooming.
      attribute.class("active:cursor-grabbing text-wrap touch-action-none"),
      attribute.class(case dragged {
        True -> "opacity-20"
        False -> ""
      }),
      event.on("pointermove", {
        use y <- decode.field("clientY", decode.float)
        use element <- decode.field("currentTarget", decode.dynamic)
        let rect = get_rect(element)
        let midpoint = rect.y + rect.height / 2

        let index = case float.truncate(y) > midpoint {
          True -> index + 1
          False -> index
        }

        decode.success(UserDraggedOverTask(to: column_type, index:))
      }),
      event.on("pointerdown", {
        use pointer_x <- decode.field("clientX", decode.float)
        use pointer_y <- decode.field("clientY", decode.float)
        use pointer_id <- decode.field("pointerId", decode.int)
        use element <- decode.field("currentTarget", decode.dynamic)

        // Release pointer so it can target element underneath the drag preview.
        release_pointer_capture(element, pointer_id)

        let rect = get_rect(element)
        let offset_x = float.truncate(pointer_x) - rect.x
        let offset_y = float.truncate(pointer_y) - rect.y

        decode.success(UserPickedUpTask(
          task: Task(task_id, task_title),
          from: column_type,
          height: rect.height,
          width: rect.width,
          pointer_x: float.truncate(pointer_x),
          pointer_y: float.truncate(pointer_y),
          offset_x:,
          offset_y:,
        ))
      }),
    ],
    [html.p([], [html.text(task_title)])],
  )
}

fn placeholder_view(height) {
  html.li(
    [
      attribute.class("border p-2 rounded-md"),
      attribute.style("height", int.to_string(height) <> "px"),
    ],
    [],
  )
}

// EXTERNAL -------------------------------------------------------------------

pub type Rect {
  Rect(
    x: Int,
    y: Int,
    width: Int,
    height: Int,
    top: Int,
    right: Int,
    bottom: Int,
    left: Int,
  )
}

@external(javascript, "./dom.ffi.mjs", "getBoundingClientRect")
fn get_rect(element: dynamic.Dynamic) -> Rect

@external(javascript, "./dom.ffi.mjs", "releasePointerCapture")
fn release_pointer_capture(element: dynamic.Dynamic, pointer_id: Int) -> Nil
