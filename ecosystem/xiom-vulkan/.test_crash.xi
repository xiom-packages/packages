module probe_sc
use xiom.vulkan;
use xiom.io;
use xiom.math;
fn main() -> Int {
  let app=create_app("P",800,600);
  match app {
    Ok(a)=>{
      var f=0;
      while f<10 && !should_close(a) {
        poll(a);
        let n1=now();let n2=now();let n3=now();
        set_clear_color(a,0.05,0.05,0.1);
        let s=begin_frame(a);
        if s==1{draw_triangle_2d(a,(math.sin(n1)*0.5+0.5)as Float32,(math.sin(n2+2.0)*0.5+0.5)as Float32,(math.sin(n3+4.0)*0.5+0.5)as Float32);end_frame(a);f=f+1;}
        elif s==-1{io.println("ERR:"+last_error());break;}
      }
      destroy_app(a);
      return 0;
    }
    Err(e)=>{io.println(e);return 1;}
  }
}
